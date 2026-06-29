import Fluent
import struct Foundation.UUID
import struct Foundation.Date

/// A single journal entry documenting a step in the Swift learning journey.
///
/// Property wrappers interact poorly with `Sendable` checking, so the model is
/// marked `@unchecked Sendable` per the Vapor template recommendation.
final class JournalEntry: Model, @unchecked Sendable {
    static let schema = "journal_entries"

    @ID(key: .id)
    var id: UUID?

    /// Human-readable title shown on cards and the entry page.
    @Field(key: "title")
    var title: String

    /// URL-friendly identifier used to route to the full entry (e.g. `my-first-view`).
    @Field(key: "slug")
    var slug: String

    /// Short description rendered on the homepage card.
    @Field(key: "excerpt")
    var excerpt: String

    /// Raw HTML for the "micro-project" showcase block (syntax sample, embedded
    /// element, or interactive UI concept). Authored by the site owner, so it is
    /// rendered unescaped on the entry page.
    @Field(key: "showcase_html")
    var showcaseHTML: String

    /// Main body text of the entry. Paragraphs are separated by blank lines.
    @Field(key: "body")
    var body: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() { }

    init(
        id: UUID? = nil,
        title: String,
        slug: String,
        excerpt: String,
        showcaseHTML: String,
        body: String
    ) {
        self.id = id
        self.title = title
        self.slug = slug
        self.excerpt = excerpt
        self.showcaseHTML = showcaseHTML
        self.body = body
    }
}
