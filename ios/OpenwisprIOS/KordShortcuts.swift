import AppIntents

struct ImportTranscriptToKordIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Transcript to Kord"
    static let description = IntentDescription("Save transcript text into Kord History and optionally create a note.")
    static let openAppWhenRun = false

    @Parameter(
        title: "Transcript",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var transcript: String

    @Parameter(title: "Title")
    var title: String?

    @Parameter(title: "Create Note")
    var createNote: Bool?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .result(dialog: "No transcript text was provided.")
        }

        let imported = SharedConfig.importExternalTranscript(
            cleaned,
            title: title ?? "Daily call transcript",
            createNote: createNote ?? true,
            dedupeByText: true
        )

        if imported {
            return .result(dialog: "Saved transcript to Kord.")
        } else {
            return .result(dialog: "Already synced to Kord.")
        }
    }
}

struct OpenKordImportIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Kord Import"
    static let description = IntentDescription("Open Kord to the Import screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedConfig.requestedTab = "import"
        return .result()
    }
}

struct KordShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportTranscriptToKordIntent(),
            phrases: [
                "Import transcript to \(.applicationName)",
                "Sync call transcript with \(.applicationName)"
            ],
            shortTitle: "Import Transcript",
            systemImageName: "tray.and.arrow.down"
        )

        AppShortcut(
            intent: OpenKordImportIntent(),
            phrases: [
                "Open import in \(.applicationName)",
                "Open call import in \(.applicationName)"
            ],
            shortTitle: "Open Import",
            systemImageName: "arrow.down.doc"
        )
    }
}
