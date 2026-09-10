import AppIntents

struct NewChavrusaNoteShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "New Chavrusa Note"
    static let description = IntentDescription("Open ChavrusaNotes ready to create a note.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedIntentCommandStore.requestNewNote()
        return .result()
    }
}

struct ChavrusaNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewChavrusaNoteShortcutIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "New chavrusa note in \(.applicationName)"
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
    }
}
