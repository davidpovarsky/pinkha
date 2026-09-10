import AppIntents
import SwiftUI
import WidgetKit

struct NewChavrusaNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Chavrusa Note"
    static let description = IntentDescription("Open ChavrusaNotes ready to create a note.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedIntentCommandStore.requestNewNote()
        return .result()
    }
}

private struct PendingCaptureEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
    let latestText: String?
}

private struct PendingCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> PendingCaptureEntry {
        PendingCaptureEntry(date: .now, pendingCount: 1, latestText: "A shared source is ready")
    }

    func getSnapshot(in context: Context, completion: @escaping (PendingCaptureEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PendingCaptureEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> PendingCaptureEntry {
        let captures = SharedCaptureStore.pending()
        return PendingCaptureEntry(
            date: .now,
            pendingCount: captures.count,
            latestText: captures.last?.text
        )
    }
}

private struct PendingCaptureWidgetView: View {
    let entry: PendingCaptureEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ChavrusaNotes", systemImage: "book.pages")
                .font(.headline)
            if entry.pendingCount > 0 {
                Text("\(entry.pendingCount) shared item\(entry.pendingCount == 1 ? "" : "s") ready")
                    .font(.subheadline)
                if let latestText = entry.latestText {
                    Text(latestText)
                        .font(.caption)
                        .lineLimit(2)
                        .privacySensitive()
                }
            } else {
                Text("Keep your learning close.")
                    .font(.subheadline)
            }
            Spacer(minLength: 0)
            Button(intent: NewChavrusaNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .buttonStyle(.plain)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct ChavrusaNotesWidget: Widget {
    let kind = "com.itorah.chavrusanotes.pending-captures"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PendingCaptureProvider()) { entry in
            PendingCaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("ChavrusaNotes")
        .description("See shared sources and start a new note.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.itorah.chavrusanotes.new-note-control") {
            ControlWidgetButton(action: NewChavrusaNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Chavrusa Note")
        .description("Open ChavrusaNotes ready to create a note.")
    }
}

@main
struct ChavrusaNotesWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChavrusaNotesWidget()
        NewNoteControl()
    }
}
