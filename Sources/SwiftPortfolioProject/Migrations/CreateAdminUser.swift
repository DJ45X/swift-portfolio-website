import Fluent

struct CreateAdminUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("admin_users")
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "username")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("admin_users").delete()
    }
}
