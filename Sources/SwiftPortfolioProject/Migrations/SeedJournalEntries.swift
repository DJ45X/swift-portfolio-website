import Fluent

/// Inserts a few starter journal entries. Because local development uses an
/// in-memory SQLite database, this seed runs on every launch to give the site
/// content to display out of the box.
struct SeedJournalEntries: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let entries = [
            JournalEntry(
                title: "Hello, SwiftUI: My First View",
                slug: "hello-swiftui-my-first-view",
                excerpt: "Where it all begins — declaring a screen as a value type and learning to trust the framework to do the drawing.",
                showcaseHTML: """
                <pre class="code-block"><code>struct GreetingView: View {
                    let name: String

                    var body: some View {
                        VStack(spacing: 8) {
                            Text("Hello, \\(name)!")
                                .font(.largeTitle)
                                .bold()
                            Text("Welcome to Swift.")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }</code></pre>
                """,
                body: """
                Coming from imperative UI work, the hardest part of SwiftUI was unlearning the habit of mutating views directly. There is no `view.text = "..."` here.

                Instead, a view is a value — a description of what the screen should look like for a given state. You hand that description to the framework and it figures out the diffing and drawing. It felt strange at first, but the payoff is that the UI can never drift out of sync with the data.

                The `body` property is the whole contract: given the current state, return the view tree. That's it.
                """
            ),
            JournalEntry(
                title: "Optionals Finally Clicked",
                slug: "optionals-finally-clicked",
                excerpt: "An interactive look at why Swift makes the absence of a value an explicit, type-checked thing rather than a runtime surprise.",
                showcaseHTML: """
                <div class="showcase-demo">
                    <p class="showcase-demo__label">Tap to unwrap an optional safely:</p>
                    <button class="showcase-demo__button" onclick="
                        const names = ['Ada', null, 'Grace', null, 'Linus'];
                        const i = Math.floor(Math.random() * names.length);
                        const value = names[i];
                        this.nextElementSibling.textContent =
                            value === null
                                ? 'value == nil → using default \\'Anonymous\\''
                                : 'if let name = value → \\'' + value + '\\'';
                    ">Unwrap</button>
                    <output class="showcase-demo__output">Result appears here.</output>
                </div>
                """,
                body: """
                For weeks I treated optionals as a chore — extra `?` and `!` symbols to sprinkle until the compiler stopped complaining. That was the wrong mental model.

                An optional is the type system being honest: this value might not be here, and you must decide what happens when it isn't. `if let` and `guard let` aren't ceremony; they are the moment you handle the empty case on purpose.

                Once I stopped reaching for the force-unwrap `!` and started treating `nil` as a real branch in my logic, whole categories of crashes simply stopped happening.
                """
            ),
            JournalEntry(
                title: "This Site Runs on Vapor",
                slug: "this-site-runs-on-vapor",
                excerpt: "Swift isn't just for apps. The journal you're reading is a server-side Swift project built with Vapor, Fluent, and Leaf.",
                showcaseHTML: """
                <pre class="code-block"><code>// The route that rendered this very page
                func show(req: Request) async throws -> View {
                    let slug = req.parameters.get("slug")!
                    guard let entry = try await JournalEntry
                        .query(on: req.db)
                        .filter(\\.$slug == slug)
                        .first()
                    else { throw Abort(.notFound) }

                    return try await req.view.render("entry", entry)
                }</code></pre>
                """,
                body: """
                Writing a web backend in the same language as my iOS experiments has been quietly motivating. The model types, the `async`/`await`, the strong typing — it's all the Swift I already know, pointed at HTTP instead of a screen.

                Fluent gives me an ORM that feels native, Leaf handles templating without dragging in a JavaScript framework, and Vapor ties it together with a clean routing API.

                The best part: every journal entry I write here is itself a small Swift exercise. The medium is the message.
                """
            )
        ]

        for entry in entries {
            try await entry.save(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        try await JournalEntry.query(on: database).delete()
    }
}
