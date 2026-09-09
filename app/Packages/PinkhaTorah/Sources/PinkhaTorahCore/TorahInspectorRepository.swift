import Foundation

@MainActor
public final class TorahInspectorRepository {
    public typealias TextFetcher = @Sendable (String, String?) async throws -> TorahTextDocument
    public typealias LinksFetcher = @Sendable (String, String?) async throws -> [TorahLinkedSource]
    public typealias TopicsFetcher = @Sendable (String, String?) async throws -> [TorahLinkedTopic]

    private let textFetcher: TextFetcher
    private let linksFetcher: LinksFetcher
    private let topicsFetcher: TopicsFetcher
    public let documentCapacity: Int
    public let relationshipCapacity: Int

    // Document cache: key is normalized "\(providerID):\(ref)"
    private var documentCache: [String: TorahTextDocument] = [:]
    // Tracks canonical keys in order of recent use (most recent at end)
    private var documentLRU: [String] = []
    // Maps canonical key to all cache alias keys associated with it
    private var canonicalAliases: [String: Set<String>] = [:]
    // In-flight single-flight text tasks
    private var inFlightDocuments: [String: Task<TorahTextDocument, Error>] = [:]

    // Links cache
    private var linksCache: [String: [TorahLinkedSource]] = [:]
    private var inFlightLinks: [String: Task<[TorahLinkedSource], Error>] = [:]

    // Topics cache
    private var topicsCache: [String: [TorahLinkedTopic]] = [:]
    private var inFlightTopics: [String: Task<[TorahLinkedTopic], Error>] = [:]

    public init(
        workspace: TorahWorkspace,
        documentCapacity: Int = 30,
        relationshipCapacity: Int = 50
    ) {
        self.textFetcher = { ref, providerID in
            try await workspace.fetchText(reference: ref, providerID: providerID)
        }
        self.linksFetcher = { ref, providerID in
            try await workspace.links(for: ref, providerID: providerID)
        }
        self.topicsFetcher = { ref, providerID in
            try await workspace.topics(for: ref, providerID: providerID)
        }
        self.documentCapacity = documentCapacity
        self.relationshipCapacity = relationshipCapacity
    }

    public init(
        documentCapacity: Int = 30,
        relationshipCapacity: Int = 50,
        textFetcher: @escaping TextFetcher,
        linksFetcher: @escaping LinksFetcher = { _, _ in [] },
        topicsFetcher: @escaping TopicsFetcher = { _, _ in [] }
    ) {
        self.textFetcher = textFetcher
        self.linksFetcher = linksFetcher
        self.topicsFetcher = topicsFetcher
        self.documentCapacity = documentCapacity
        self.relationshipCapacity = relationshipCapacity
    }

    private func normalizedKey(providerID: String?, reference: String) -> String {
        "\(providerID ?? ""):\(reference)"
    }

    // MARK: - Document Loading & Caching

    public func cachedDocument(for reference: String, providerID: String? = nil) -> TorahTextDocument? {
        let key = normalizedKey(providerID: providerID, reference: reference)
        guard let doc = documentCache[key] else { return nil }
        touch(canonicalKey: normalizedKey(providerID: doc.providerID, reference: doc.canonicalRef))
        return doc
    }

    public func document(for reference: String, providerID: String? = nil) async throws -> TorahTextDocument {
        if let cached = cachedDocument(for: reference, providerID: providerID) {
            return cached
        }

        let key = normalizedKey(providerID: providerID, reference: reference)
        if let inFlight = inFlightDocuments[key] {
            return try await inFlight.value
        }

        let fetcher = self.textFetcher
        let task = Task<TorahTextDocument, Error> {
            try await fetcher(reference, providerID)
        }
        inFlightDocuments[key] = task

        do {
            let doc = try await task.value
            inFlightDocuments.removeValue(forKey: key)
            storeDocument(doc, requestedRef: reference, providerID: providerID)
            return doc
        } catch {
            inFlightDocuments.removeValue(forKey: key)
            throw error
        }
    }

    private func storeDocument(_ doc: TorahTextDocument, requestedRef: String, providerID: String?) {
        let pId = providerID ?? doc.providerID
        let canonicalKey = normalizedKey(providerID: pId, reference: doc.canonicalRef)
        let requestedKey = normalizedKey(providerID: pId, reference: requestedRef)
        let sectionKey = normalizedKey(providerID: pId, reference: doc.sectionRef)
        let docRequestedKey = normalizedKey(providerID: pId, reference: doc.requestedRef)

        var aliases: Set<String> = [canonicalKey, requestedKey, sectionKey, docRequestedKey]
        if let existing = canonicalAliases[canonicalKey] {
            aliases.formUnion(existing)
        }
        canonicalAliases[canonicalKey] = aliases

        for alias in aliases {
            documentCache[alias] = doc
        }

        touch(canonicalKey: canonicalKey)
        evictDocumentsIfNeeded()
    }

    private func touch(canonicalKey: String) {
        documentLRU.removeAll(where: { $0 == canonicalKey })
        documentLRU.append(canonicalKey)
    }

    private func evictDocumentsIfNeeded() {
        while documentLRU.count > documentCapacity {
            let oldestCanonicalKey = documentLRU.removeFirst()
            if let aliases = canonicalAliases.removeValue(forKey: oldestCanonicalKey) {
                for alias in aliases {
                    documentCache.removeValue(forKey: alias)
                }
            }
        }
    }

    // MARK: - Links Loading & Caching

    public func cachedLinks(for reference: String, providerID: String? = nil) -> [TorahLinkedSource]? {
        let key = normalizedKey(providerID: providerID, reference: reference)
        return linksCache[key]
    }

    public func links(for reference: String, providerID: String? = nil) async throws -> [TorahLinkedSource] {
        if let cached = cachedLinks(for: reference, providerID: providerID) {
            return cached
        }

        let key = normalizedKey(providerID: providerID, reference: reference)
        if let inFlight = inFlightLinks[key] {
            return try await inFlight.value
        }

        let fetcher = self.linksFetcher
        let task = Task<[TorahLinkedSource], Error> {
            try await fetcher(reference, providerID)
        }
        inFlightLinks[key] = task

        do {
            let values = try await task.value
            inFlightLinks.removeValue(forKey: key)
            linksCache[key] = values
            return values
        } catch {
            inFlightLinks.removeValue(forKey: key)
            throw error
        }
    }

    // MARK: - Topics Loading & Caching

    public func cachedTopics(for reference: String, providerID: String? = nil) -> [TorahLinkedTopic]? {
        let key = normalizedKey(providerID: providerID, reference: reference)
        return topicsCache[key]
    }

    public func topics(for reference: String, providerID: String? = nil) async throws -> [TorahLinkedTopic] {
        if let cached = cachedTopics(for: reference, providerID: providerID) {
            return cached
        }

        let key = normalizedKey(providerID: providerID, reference: reference)
        if let inFlight = inFlightTopics[key] {
            return try await inFlight.value
        }

        let fetcher = self.topicsFetcher
        let task = Task<[TorahLinkedTopic], Error> {
            try await fetcher(reference, providerID)
        }
        inFlightTopics[key] = task

        do {
            let values = try await task.value
            inFlightTopics.removeValue(forKey: key)
            topicsCache[key] = values
            return values
        } catch {
            inFlightTopics.removeValue(forKey: key)
            throw error
        }
    }
}
