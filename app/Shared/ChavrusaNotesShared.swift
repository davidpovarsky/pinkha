import Foundation

enum ChavrusaNotesIdentity {
    static let privateAppGroup = "group.com.itorah.chavrusanotes"
    static let sharedITorahAppGroup = "group.com.itorah.shared"
    static let newNoteCommandKey = "com.itorah.chavrusanotes.command.new-note"
}

struct SharedCapture: Codable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let sourceURL: URL?
    let createdAt: Date

    init(text: String, sourceURL: URL? = nil) {
        self.id = UUID()
        self.text = text
        self.sourceURL = sourceURL
        self.createdAt = Date()
    }
}

enum SharedCaptureStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static var directoryURL: URL? {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ChavrusaNotesIdentity.privateAppGroup
        ) else { return nil }
        let directory = root.appendingPathComponent("SharedCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    @discardableResult
    static func save(text: String, sourceURL: URL? = nil) throws -> SharedCapture {
        guard let directoryURL else { throw SharedCaptureError.appGroupUnavailable }
        let capture = SharedCapture(text: text, sourceURL: sourceURL)
        let destination = directoryURL
            .appendingPathComponent(capture.id.uuidString)
            .appendingPathExtension("json")
        try encoder.encode(capture).write(to: destination, options: .atomic)
        return capture
    }

    static func pending() -> [SharedCapture] {
        guard let directoryURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
              )
        else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SharedCapture.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func remove(_ captures: [SharedCapture]) {
        guard let directoryURL else { return }
        for capture in captures {
            let url = directoryURL
                .appendingPathComponent(capture.id.uuidString)
                .appendingPathExtension("json")
            try? FileManager.default.removeItem(at: url)
        }
    }
}

enum SharedIntentCommandStore {
    static func requestNewNote() {
        UserDefaults(suiteName: ChavrusaNotesIdentity.privateAppGroup)?
            .set(true, forKey: ChavrusaNotesIdentity.newNoteCommandKey)
    }

    static func consumeNewNoteRequest() -> Bool {
        guard let defaults = UserDefaults(suiteName: ChavrusaNotesIdentity.privateAppGroup),
              defaults.bool(forKey: ChavrusaNotesIdentity.newNoteCommandKey)
        else { return false }
        defaults.removeObject(forKey: ChavrusaNotesIdentity.newNoteCommandKey)
        return true
    }
}

enum SharedCaptureError: Error {
    case appGroupUnavailable
}
