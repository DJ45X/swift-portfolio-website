import Fluent
import Vapor
import struct Foundation.Date
import class Foundation.DateFormatter

struct JournalController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: self.index)
        routes.get("entries", ":slug", use: self.show)
    }

    /// Homepage — a feed of the most recent journal entries as cards.
    @Sendable
    func index(req: Request) async throws -> View {
        let entries = try await JournalEntry.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .all()

        let cards = entries.map {
            CardContext(
                title: $0.title,
                slug: $0.slug,
                excerpt: $0.excerpt,
                date: Self.format($0.createdAt)
            )
        }

        return try await req.view.render(
            "index",
            IndexContext(title: "DJ's Swift Journey", entries: cards)
        )
    }

    /// Full view for a single entry, including its micro-project showcase block.
    @Sendable
    func show(req: Request) async throws -> View {
        let slug = req.parameters.get("slug") ?? ""

        guard let entry = try await JournalEntry.query(on: req.db)
            .filter(\.$slug == slug)
            .first()
        else {
            throw Abort(.notFound)
        }

        let paragraphs = entry.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let context = EntryContext(
            title: "\(entry.title) · DJ's Swift Journey",
            entry: EntryDetail(
                title: entry.title,
                date: Self.format(entry.createdAt),
                showcaseHTML: entry.showcaseHTML,
                paragraphs: paragraphs
            )
        )

        return try await req.view.render("entry", context)
    }

    /// Formats a stored timestamp into a readable date such as "Jun 26, 2026".
    private static func format(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - View Contexts

private struct IndexContext: Content {
    let title: String
    let entries: [CardContext]
}

private struct CardContext: Content {
    let title: String
    let slug: String
    let excerpt: String
    let date: String
}

private struct EntryContext: Content {
    let title: String
    let entry: EntryDetail
}

private struct EntryDetail: Content {
    let title: String
    let date: String
    let showcaseHTML: String
    let paragraphs: [String]
}
