import Fluent

struct CreateJournalEntry: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("journal_entries")
            .id()
            .field("title", .string, .required)
            .field("slug", .string, .required)
            .field("excerpt", .string, .required)
            .field("showcase_html", .string, .required)
            .field("body", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "slug")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("journal_entries").delete()
    }
}
