import Social
import UniformTypeIdentifiers
import WidgetKit

final class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool {
        let hasComment = !(contentText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasAttachment = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap(\.attachments)
            .isEmpty == false
        return hasComment || hasAttachment
    }

    override func didSelectPost() {
        let comment = (contentText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let attachment = try await firstAttachment()
                let pieces = [comment, attachment.text]
                    .filter { !$0.isEmpty }
                guard !pieces.isEmpty else { throw ShareError.noContent }
                try SharedCaptureStore.save(
                    text: pieces.joined(separator: "\n\n"),
                    sourceURL: attachment.url
                )
                WidgetCenter.shared.reloadAllTimelines()
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                extensionContext?.cancelRequest(withError: error)
            }
        }
    }

    override func configurationItems() -> [Any]! { [] }

    private func firstAttachment() async throws -> (text: String, url: URL?) {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap(\.attachments) ?? []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            let value = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            if let url = value as? URL { return (url.absoluteString, url) }
            if let text = value as? String, let url = URL(string: text) { return (text, url) }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            let value = try await provider.loadItem(forTypeIdentifier: UTType.text.identifier)
            if let text = value as? String { return (text, nil) }
            if let text = value as? NSAttributedString { return (text.string, nil) }
        }
        return ("", nil)
    }
}

private enum ShareError: Error {
    case noContent
}
