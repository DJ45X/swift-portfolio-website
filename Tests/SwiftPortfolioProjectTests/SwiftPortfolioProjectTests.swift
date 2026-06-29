@testable import SwiftPortfolioProject
import VaporTesting
import Testing
import Fluent

@Suite("App Tests with DB", .serialized)
struct SwiftPortfolioProjectTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Homepage renders and lists the seeded entries")
    func homepageListsEntries() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("DJ's Swift Journey"))
                #expect(res.body.string.contains("Hello, SwiftUI: My First View"))
            })
        }
    }

    @Test("An individual entry page renders its showcase and body")
    func entryPageRenders() async throws {
        try await withApp { app in
            try await app.testing().test(
                .GET,
                "entries/hello-swiftui-my-first-view",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.body.string.contains("Micro-project"))
                    #expect(res.body.string.contains("GreetingView"))
                }
            )
        }
    }

    @Test("An unknown slug returns 404")
    func unknownSlugReturnsNotFound() async throws {
        try await withApp { app in
            try await app.testing().test(
                .GET,
                "entries/does-not-exist",
                afterResponse: { res async in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    // MARK: - Admin bootstrap & auth

    private func tokenFilePath(_ app: Application) -> String {
        app.directory.workingDirectory + AdminController.bootstrapTokenFile
    }

    @Test("/admin redirects to setup when no admin exists")
    func adminRedirectsToSetup() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "admin", afterResponse: { res async in
                #expect((300..<400).contains(res.status.code))
                #expect(res.headers.first(name: .location) == "/admin/setup")
            })
        }
    }

    @Test("Protected dashboard redirects unauthenticated users to login")
    func dashboardRedirectsWhenUnauthenticated() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "admin/dashboard", afterResponse: { res async in
                #expect((300..<400).contains(res.status.code))
                #expect(res.headers.first(name: .location) == "/login")
            })
        }
    }

    @Test("Setup creates the first admin via the bootstrap token, then locks out")
    func setupBootstrapFlow() async throws {
        try await withApp { app in
            let path = tokenFilePath(app)
            try? FileManager.default.removeItem(atPath: path)

            // GET setup writes the bootstrap token to disk.
            try await app.testing().test(.GET, "admin/setup", afterResponse: { res async in
                #expect(res.status == .ok)
            })

            let token = try String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!token.isEmpty)

            // A wrong token re-renders the token form and creates no admin.
            try await app.testing().test(.POST, "admin/setup", beforeRequest: { req in
                try req.content.encode(["token": "totally-wrong"], as: .urlEncodedForm)
            }, afterResponse: { res async in
                #expect(res.status == .ok)
            })
            let afterBadToken = try await AdminUser.query(on: app.db).count()
            #expect(afterBadToken == 0)

            // The correct token + credentials creates the admin and deletes the file.
            try await app.testing().test(.POST, "admin/setup", beforeRequest: { req in
                try req.content.encode([
                    "token": token,
                    "username": "djadmin",
                    "password": "supersecret",
                    "confirmPassword": "supersecret"
                ], as: .urlEncodedForm)
            }, afterResponse: { res async in
                #expect((300..<400).contains(res.status.code))
                #expect(res.headers.first(name: .location) == "/admin/dashboard")
            })

            let admins = try await AdminUser.query(on: app.db).all()
            #expect(admins.count == 1)
            #expect(admins.first?.username == "djadmin")
            // Password must be stored as an Argon2id hash, never plaintext.
            #expect(admins.first?.passwordHash.hasPrefix("$argon2id$") == true)
            #expect(admins.first?.passwordHash.contains("supersecret") == false)
            #expect(FileManager.default.fileExists(atPath: path) == false)

            // Lockout: setup now redirects to login instead of allowing a 2nd admin.
            try await app.testing().test(.GET, "admin/setup", afterResponse: { res async in
                #expect((300..<400).contains(res.status.code))
                #expect(res.headers.first(name: .location) == "/login")
            })
        }
    }

    @Test("The stored Argon2id hash verifies the correct password")
    func argon2HashVerifies() async throws {
        let hasher = Argon2PasswordHasher()
        let hash = try hasher.hashToString("supersecret")
        #expect(hash.hasPrefix("$argon2id$"))
        #expect(try hasher.verify(Array("supersecret".utf8), created: Array(hash.utf8)))
        #expect(try hasher.verify(Array("wrong".utf8), created: Array(hash.utf8)) == false)
    }

    @Test("Deleting an entry is protected and does nothing for unauthenticated users")
    func deleteRequiresAuth() async throws {
        try await withApp { app in
            let before = try await JournalEntry.query(on: app.db).count()
            #expect(before > 0)

            try await app.testing().test(
                .POST,
                "admin/entries/hello-swiftui-my-first-view/delete",
                afterResponse: { res async in
                    // Redirected to login rather than performing the delete.
                    #expect((300..<400).contains(res.status.code))
                    #expect(res.headers.first(name: .location) == "/login")
                }
            )

            let after = try await JournalEntry.query(on: app.db).count()
            #expect(after == before)
        }
    }

    @Test("Homepage hides the delete button from guests")
    func homepageHidesDeleteForGuests() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("card__delete") == false)
                #expect(res.body.string.contains("data-delete") == false)
            })
        }
    }

    @Test("A logged-in admin can delete an entry and is sent back to the dashboard")
    func authenticatedDeleteFlow() async throws {
        try await withApp { app in
            // Seed an admin to log in as.
            let hash = try Argon2PasswordHasher().hashToString("password123")
            try await AdminUser(username: "djadmin", passwordHash: hash).save(on: app.db)

            let slug = "this-site-runs-on-vapor"
            #expect(try await JournalEntry.query(on: app.db).filter(\.$slug == slug).first() != nil)

            // Log in and capture the session cookie.
            var sessionCookie = ""
            try await app.testing().test(.POST, "login", beforeRequest: { req in
                try req.content.encode(
                    ["username": "djadmin", "password": "password123"],
                    as: .urlEncodedForm
                )
            }, afterResponse: { res async in
                #expect((300..<400).contains(res.status.code))
                #expect(res.headers.first(name: .location) == "/admin/dashboard")
                let raw = res.headers.first(name: .setCookie) ?? ""
                sessionCookie = String(raw.prefix(while: { $0 != ";" }))
            })
            #expect(!sessionCookie.isEmpty)

            // Delete the entry while authenticated.
            try await app.testing().test(.POST, "admin/entries/\(slug)/delete", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .cookie, value: sessionCookie)
            }, afterResponse: { res async in
                #expect((300..<400).contains(res.status.code))
                let location = res.headers.first(name: .location) ?? ""
                #expect(location.hasPrefix("/admin/dashboard"))
            })

            // The entry is actually gone.
            let remaining = try await JournalEntry.query(on: app.db).filter(\.$slug == slug).first()
            #expect(remaining == nil)
        }
    }
}
