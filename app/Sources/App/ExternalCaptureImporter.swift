import CoreSpotlight
import PinkhaCore
import PinkhaFFI
import UniformTypeIdentifiers
import WidgetKit

extension PinkhaStore {
    /// Converts payloads written by the Share extension into ordinary leaves.
    /// A capture is deleted from the App Group inbox only after every database
    /// write succeeds, so a crash or interrupted import remains retryable.
    func importPendingSharedCaptures() {
        guard let api else { return }
        var imported: [SharedCapture] = []

        for capture in SharedCaptureStore.pending() {
            do {
                let title = Self.captureTitle(from: capture)
                let leafID = try api.createLeaf(title: title)
                let paragraphs = capture.text
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                for paragraph in paragraphs {
                    let content = BlockContentFfi.text([
                        InlineTextFfi(content: paragraph, styles: [])
                    ])
                    let data = try JSONEncoder().encode(content)
                    guard let json = String(data: data, encoding: .utf8) else { continue }
                    _ = try api.addBlock(leafId: leafID, blockContentJson: json)
                }

                imported.append(capture)
                Self.indexCapture(capture, leafID: leafID, title: title)
            } catch {
                errorMessage = "Could not import a shared item: \(error.localizedDescription)"
            }
        }

        guard !imported.isEmpty else { return }
        SharedCaptureStore.remove(imported)
        load()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func captureTitle(from capture: SharedCapture) -> String {
        let firstLine = capture.text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = capture.sourceURL?.host ?? "Shared Note"
        return String((firstLine ?? fallback).prefix(80))
    }

    private static func indexCapture(_ capture: SharedCapture, leafID: String, title: String) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = String(capture.text.prefix(500))
        if let sourceURL = capture.sourceURL { attributes.url = sourceURL }
        let item = CSSearchableItem(
            uniqueIdentifier: leafID,
            domainIdentifier: "com.itorah.chavrusanotes.notes",
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }
}
