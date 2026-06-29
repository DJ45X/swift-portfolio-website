import Fluent
import FluentSQLiteDriver
import Foundation
import Leaf
import Vapor

/// configures your application
func configure(_ app: Application) async throws {
    // When launched from Xcode, the process working directory points at
    // DerivedData instead of the package root, so Leaf templates and static
    // assets can't be found ("No template found for index"). Point the app at
    // the real package root when the detected directory is missing Resources.
    fixWorkingDirectoryIfNeeded(app)

    // Serve static assets (CSS, JS) from the /Public folder.
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Database. In-memory SQLite keeps local development fast and dependency-free
    // on Apple Silicon (rebuilt + re-seeded each launch). To persist data for
    // deployment, set the environment variable SQLITE_FILE=1 (or swap the line
    // below for `.file("db.sqlite")`).
    if Environment.get("SQLITE_FILE") != nil {
        app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)
    } else {
        app.databases.use(DatabaseConfigurationFactory.sqlite(.memory), as: .sqlite)
    }

    // Sessions + Argon2id-based session authentication for the admin area.
    app.passwords.use { _ in Argon2PasswordHasher() }
    app.sessions.use(.memory)
    app.middleware.use(app.sessions.middleware)
    app.middleware.use(AdminUser.sessionAuthenticator())

    app.migrations.add(CreateJournalEntry())
    app.migrations.add(SeedJournalEntries())
    app.migrations.add(CreateAdminUser())

    // Run migrations automatically since the in-memory store starts empty.
    try await app.autoMigrate()

    app.views.use(.leaf)

    // register routes
    try routes(app)
}

/// Ensures the app's working directory contains the `Resources` and `Public`
/// folders. If the auto-detected directory doesn't (as when run from Xcode),
/// the package root is derived from this source file's location at build time.
private func fixWorkingDirectoryIfNeeded(_ app: Application) {
    let fileManager = FileManager.default

    // If the detected working directory already has our views, we're good.
    if fileManager.fileExists(atPath: app.directory.viewsDirectory) {
        return
    }

    // This file lives at <packageRoot>/Sources/SwiftPortfolioProject/configure.swift.
    let marker = "Sources/SwiftPortfolioProject/configure.swift"
    let thisFile = #filePath
    guard thisFile.hasSuffix(marker) else { return }

    let packageRoot = String(thisFile.dropLast(marker.count))
    guard fileManager.fileExists(atPath: packageRoot + "Resources/Views") else { return }

    app.directory = DirectoryConfiguration(workingDirectory: packageRoot)
    app.logger.notice("Adjusted working directory to package root: \(packageRoot)")
}
