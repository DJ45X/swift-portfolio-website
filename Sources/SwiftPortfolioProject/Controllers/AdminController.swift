import Fluent
import Foundation
import Vapor

/// Handles the out-of-band admin bootstrap, login/logout, and the entry-authoring
/// dashboard.
struct AdminController: RouteCollection {
    /// File (in the project root) that holds the one-time bootstrap token.
    static let bootstrapTokenFile = "admin_bootstrap_token.txt"

    func boot(routes: any RoutesBuilder) throws {
        // Public entry points.
        routes.get("admin", use: self.adminIndex)
        routes.get("admin", "setup", use: self.setupForm)
        routes.post("admin", "setup", use: self.setupSubmit)

        routes.get("login", use: self.loginForm)
        routes.grouped(AdminUser.credentialsAuthenticator())
            .post("login", use: self.loginSubmit)
        routes.post("logout", use: self.logout)

        // Session-protected admin area: unauthenticated requests go to /login.
        let protected = routes.grouped(AdminUser.redirectMiddleware(path: "/login"))
        protected.get("admin", "dashboard", use: self.dashboard)
        protected.post("admin", "entries", use: self.createEntry)
        protected.post("admin", "entries", ":slug", "delete", use: self.deleteEntry)
    }

    // MARK: - Bootstrap / Setup

    /// `/admin` — routes to setup (no admin yet), the dashboard (logged in), or login.
    @Sendable
    func adminIndex(req: Request) async throws -> Response {
        if try await AdminUser.query(on: req.db).count() == 0 {
            return req.redirect(to: "/admin/setup")
        }
        if req.auth.has(AdminUser.self) {
            return req.redirect(to: "/admin/dashboard")
        }
        return req.redirect(to: "/login")
    }

    /// `GET /admin/setup` — generate (or reuse) the bootstrap token and ask for it.
    @Sendable
    func setupForm(req: Request) async throws -> Response {
        // Lockout: setup is unavailable once an admin exists.
        guard try await AdminUser.query(on: req.db).count() == 0 else {
            return req.redirect(to: "/login")
        }

        try ensureBootstrapToken(req)

        let view = try await req.view.render(
            "setup-token",
            SetupTokenContext(title: "Set up admin · DJ's Swift Journey", error: nil)
        )
        return try await view.encodeResponse(for: req)
    }

    /// `POST /admin/setup` — two-stage: verify the token, then create the account.
    @Sendable
    func setupSubmit(req: Request) async throws -> Response {
        guard try await AdminUser.query(on: req.db).count() == 0 else {
            return req.redirect(to: "/login")
        }

        let form = try req.content.decode(SetupForm.self)
        let submittedToken = form.token.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stage 1: validate the token against the file.
        guard let storedToken = readBootstrapToken(req), !storedToken.isEmpty,
              constantTimeEquals(storedToken, submittedToken) else {
            let view = try await req.view.render(
                "setup-token",
                SetupTokenContext(
                    title: "Set up admin · DJ's Swift Journey",
                    error: "That token doesn't match. Open \(Self.bootstrapTokenFile) and paste the exact value."
                )
            )
            return try await view.encodeResponse(for: req)
        }

        let username = (form.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = form.password ?? ""

        // Stage 2a: token valid but no credentials yet — show the account form.
        guard !username.isEmpty, !password.isEmpty else {
            let view = try await req.view.render(
                "setup-account",
                SetupAccountContext(title: "Create admin · DJ's Swift Journey", token: submittedToken, error: nil)
            )
            return try await view.encodeResponse(for: req)
        }

        // Stage 2b: validate the chosen credentials.
        if let error = validateCredentials(username: username, password: password, confirm: form.confirmPassword) {
            let view = try await req.view.render(
                "setup-account",
                SetupAccountContext(title: "Create admin · DJ's Swift Journey", token: submittedToken, error: error)
            )
            return try await view.encodeResponse(for: req)
        }

        // Create the admin, hashing the password with Argon2id.
        let passwordHash = try Argon2PasswordHasher().hashToString(password)
        let user = AdminUser(username: username, passwordHash: passwordHash)
        try await user.save(on: req.db)

        // The token is single-use — delete the file now that an admin exists.
        deleteBootstrapToken(req)

        // Log the new admin straight in (the session authenticator persists this).
        req.auth.login(user)
        return req.redirect(to: "/admin/dashboard")
    }

    // MARK: - Login / Logout

    @Sendable
    func loginForm(req: Request) async throws -> View {
        try await req.view.render(
            "login",
            LoginContext(title: "Log in · DJ's Swift Journey", error: nil)
        )
    }

    @Sendable
    func loginSubmit(req: Request) async throws -> Response {
        // The credentials authenticator ran already; it logs the user in on success.
        guard req.auth.has(AdminUser.self) else {
            let view = try await req.view.render(
                "login",
                LoginContext(title: "Log in · DJ's Swift Journey", error: "Invalid username or password.")
            )
            return try await view.encodeResponse(for: req)
        }
        return req.redirect(to: "/admin/dashboard")
    }

    @Sendable
    func logout(req: Request) async throws -> Response {
        req.auth.logout(AdminUser.self)
        req.session.destroy()
        return req.redirect(to: "/login")
    }

    // MARK: - Dashboard

    @Sendable
    func dashboard(req: Request) async throws -> View {
        try await renderDashboard(
            req,
            error: nil,
            published: req.query[String.self, at: "published"],
            deleted: req.query[String.self, at: "deleted"]
        )
    }

    @Sendable
    func createEntry(req: Request) async throws -> Response {
        try req.auth.require(AdminUser.self)

        let form = try req.content.decode(EntryForm.self)
        let title = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = form.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = form.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let showcase = (form.showcaseHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !excerpt.isEmpty, !body.isEmpty else {
            let view = try await renderDashboard(
                req,
                error: "Title, excerpt, and content are all required.",
                published: nil,
                deleted: nil
            )
            return try await view.encodeResponse(for: req)
        }

        let slug = try await uniqueSlug(from: title, on: req.db)
        let entry = JournalEntry(
            title: title,
            slug: slug,
            excerpt: excerpt,
            showcaseHTML: showcase,
            body: body
        )
        try await entry.save(on: req.db)

        return req.redirect(to: "/admin/dashboard?published=\(slug)")
    }

    /// Deletes a journal entry by slug. Protected — admins only.
    @Sendable
    func deleteEntry(req: Request) async throws -> Response {
        try req.auth.require(AdminUser.self)

        let slug = req.parameters.get("slug") ?? ""

        // Idempotent: deleting an entry that's already gone is a graceful no-op
        // rather than a 404, so a double-submit can't surface an error page.
        if let entry = try await JournalEntry.query(on: req.db)
            .filter(\.$slug == slug)
            .first() {
            try await entry.delete(on: req.db)
        }

        return req.redirect(to: "/admin/dashboard?deleted=\(slug)")
    }

    // MARK: - Dashboard rendering helper

    private func renderDashboard(_ req: Request, error: String?, published: String?, deleted: String?) async throws -> View {
        let user = try req.auth.require(AdminUser.self)
        let recent = try await JournalEntry.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .limit(10)
            .all()

        let items = recent.map {
            DashboardItem(title: $0.title, slug: $0.slug, date: Self.format($0.createdAt))
        }

        return try await req.view.render(
            "dashboard",
            DashboardContext(
                title: "Dashboard · DJ's Swift Journey",
                username: user.username,
                entries: items,
                error: error,
                published: published,
                deleted: deleted
            )
        )
    }

    // MARK: - Bootstrap token helpers

    private func bootstrapTokenPath(_ req: Request) -> String {
        req.application.directory.workingDirectory + Self.bootstrapTokenFile
    }

    /// Writes a fresh token only if one isn't already on disk, so refreshing the
    /// setup page doesn't invalidate a token the user has already copied.
    private func ensureBootstrapToken(_ req: Request) throws {
        let path = bootstrapTokenPath(req)
        if let existing = readBootstrapToken(req), !existing.isEmpty { return }

        let token = Self.randomToken()
        try token.write(toFile: path, atomically: true, encoding: .utf8)
        req.logger.notice("Admin bootstrap token written to \(path)")
    }

    private func readBootstrapToken(_ req: Request) -> String? {
        let path = bootstrapTokenPath(req)
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deleteBootstrapToken(_ req: Request) {
        try? FileManager.default.removeItem(atPath: bootstrapTokenPath(req))
    }

    private static func randomToken() -> String {
        // Ambiguous characters (0/O, 1/l/I) are excluded to ease manual copying.
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        return String((0..<48).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Validation & utilities

    private func validateCredentials(username: String, password: String, confirm: String?) -> String? {
        if username.count < 3 {
            return "Username must be at least 3 characters."
        }
        if password.count < 8 {
            return "Password must be at least 8 characters."
        }
        if let confirm, confirm != password {
            return "Passwords don't match."
        }
        return nil
    }

    /// Length-independent comparison guard against trivial timing oracles.
    private func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<a.count {
            difference |= a[i] ^ b[i]
        }
        return difference == 0
    }

    private func uniqueSlug(from title: String, on db: any Database) async throws -> String {
        var base = Self.slugify(title)
        if base.isEmpty { base = "entry" }

        var candidate = base
        var suffix = 2
        while try await JournalEntry.query(on: db).filter(\.$slug == candidate).first() != nil {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func slugify(_ input: String) -> String {
        let mapped = input.lowercased().map { character -> Character in
            (character.isLetter || character.isNumber) ? character : "-"
        }
        var slug = String(mapped)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Form payloads

private struct SetupForm: Content {
    var token: String
    var username: String?
    var password: String?
    var confirmPassword: String?
}

private struct EntryForm: Content {
    var title: String
    var excerpt: String
    var body: String
    var showcaseHTML: String?
}

// MARK: - View contexts

private struct SetupTokenContext: Content {
    let title: String
    let error: String?
}

private struct SetupAccountContext: Content {
    let title: String
    let token: String
    let error: String?
}

private struct LoginContext: Content {
    let title: String
    let error: String?
}

private struct DashboardContext: Content {
    let title: String
    let username: String
    let entries: [DashboardItem]
    let error: String?
    let published: String?
    let deleted: String?
}

private struct DashboardItem: Content {
    let title: String
    let slug: String
    let date: String
}
