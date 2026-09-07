import Foundation

private func jsonObject(_ data: Data) throws -> Any {
    do { return try JSONSerialization.jsonObject(with: data) }
    catch { throw TorahError.malformedResponse }
}

private func jsonString(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

private func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
    for key in keys {
        guard let value = dictionary[key] as? String else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return nil
}

private func localizedTitle(_ value: Any?) -> (he: String?, en: String?) {
    if let text = value as? String { return (text, text) }
    if let value = value as? [String: Any] {
        return (firstString(value, keys: ["he", "hebrew", "primary_he"]), firstString(value, keys: ["en", "english", "primary_en"]))
    }
    return (nil, nil)
}

public struct SefariaReferenceProvider: ReferenceProvider {
    public let providerID = "sefaria"
    private let client: SefariaClient
    public init(client: SefariaClient = SefariaClient()) { self.client = client }

    public func suggestReferences(query: String, limit: Int) async throws -> [ReferenceCandidate] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let (data, response) = try await client.get(pathSegments: ["api", "name", query], query: [
            URLQueryItem(name: "type", value: "ref"), URLQueryItem(name: "limit", value: String(limit))
        ])
        guard response.statusCode == 200 else { throw TorahError.network("Sefaria returned HTTP \(response.statusCode).") }
        guard let root = try jsonObject(data) as? [String: Any] else { throw TorahError.malformedResponse }
        let values = root["completion_objects"] as? [[String: Any]] ?? []
        return values.compactMap { value in
            guard let key = value["key"] as? String,
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let title = (value["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReferenceCandidate(id: key, label: title?.isEmpty == false ? title! : key)
        }
    }

    public func resolveReference(_ input: String) async throws -> ResolvedReference {
        let (data, response) = try await client.get(pathSegments: ["api", "ref", input])
        guard response.statusCode == 200 else { throw TorahError.invalidReference }
        guard let root = try jsonObject(data) as? [String: Any] else { throw TorahError.malformedResponse }
        guard root["is_ref"] as? Bool == true else { throw TorahError.invalidReference }
        guard let canonical = firstString(root, keys: ["normalized", "ref"]) else { throw TorahError.invalidReference }
        let he = firstString(root, keys: ["hebrew", "heRef"]) ?? canonical
        let navigation = root["navigation_refs"] as? [String: Any]
        return ResolvedReference(
            canonical: canonical,
            labelHe: he,
            labelEn: canonical,
            payload: jsonString(root),
            urlRef: firstString(root, keys: ["url_ref", "url"]),
            nodeType: firstString(root, keys: ["node_type"]),
            depth: root["depth"] as? Int,
            startIndexes: root["start_indexes"] as? [Int] ?? [],
            endIndexes: root["end_indexes"] as? [Int] ?? [],
            firstAvailableSectionRef: navigation.flatMap { firstString($0, keys: ["first_available_section_ref"]) }
        )
    }
}

public struct SefariaTopicProvider: TopicProvider {
    public let providerID = "sefaria"
    private let client: SefariaClient
    private let store: TorahStore
    private let ttl: TimeInterval
    public init(client: SefariaClient = SefariaClient(), store: TorahStore, ttl: TimeInterval = 7 * 24 * 60 * 60) {
        self.client = client; self.store = store; self.ttl = ttl
    }

    public func suggestTopics(query: String, limit: Int) async throws -> [TopicCandidate] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let local = try await store.searchTopics(providerID: providerID, query: query, limit: limit)
        if !local.isEmpty { return local }
        let (data, response) = try await client.get(pathSegments: ["api", "name", query], query: [
            URLQueryItem(name: "type", value: "Topic"), URLQueryItem(name: "limit", value: String(limit))
        ])
        guard response.statusCode == 200,
              let root = try jsonObject(data) as? [String: Any] else { throw TorahError.malformedResponse }
        let values = root["completion_objects"] as? [[String: Any]] ?? []
        return values.compactMap(Self.decodeTopic)
    }

    public func resolveTopic(id: String) async throws -> ResolvedTopic {
        let (data, response) = try await client.get(pathSegments: ["api", "v2", "topics", id])
        guard response.statusCode == 200, let root = try jsonObject(data) as? [String: Any],
              let slug = firstString(root, keys: ["slug"]) else { throw TorahError.noResults }
        let title = localizedTitle(root["primaryTitle"] ?? root["titles"])
        let he = title.he ?? firstString(root, keys: ["primaryTitle", "slug"]) ?? slug
        return ResolvedTopic(slug: slug, labelHe: he, labelEn: title.en, payload: jsonString(root))
    }

    public func refreshTopicIndexIfNeeded() async throws {
        if try await store.cached(providerID: providerID, key: "topic-index-version") != nil { return }
        let (data, response) = try await client.get(pathSegments: ["api", "topics"], query: [
            URLQueryItem(name: "limit", value: "0"), URLQueryItem(name: "minify", value: "1")
        ])
        guard response.statusCode == 200 else { throw TorahError.network("Sefaria returned HTTP \(response.statusCode).") }
        let object = try jsonObject(data)
        let rows: [[String: Any]]
        if let direct = object as? [[String: Any]] { rows = direct }
        else if let root = object as? [String: Any] { rows = (root["topics"] as? [[String: Any]]) ?? [] }
        else { throw TorahError.malformedResponse }
        let decoded = rows.compactMap(Self.decodeTopic)
        guard !decoded.isEmpty else { throw TorahError.malformedResponse }
        let payloads = Dictionary(uniqueKeysWithValues: zip(decoded, rows).map { ($0.0.id, jsonString($0.1)) })
        try await store.replaceTopics(providerID: providerID, topics: decoded, payloads: payloads)
        try await store.cache(providerID: providerID, key: "topic-index-version", payload: "{}", expiresAt: Date().addingTimeInterval(ttl))
    }

    private static func decodeTopic(_ value: [String: Any]) -> TopicCandidate? {
        guard let slug = firstString(value, keys: ["slug", "key", "id"]) else { return nil }
        let title = localizedTitle(value["primaryTitle"] ?? value["title"])
        let he = title.he ?? firstString(value, keys: ["he", "title", "label"]) ?? slug
        return TopicCandidate(id: slug, labelHe: he, labelEn: title.en ?? firstString(value, keys: ["en"]))
    }
}

public struct SefariaLexicalProvider: LexicalProvider {
    public let providerID = "sefaria"
    private let client: SefariaClient
    public init(client: SefariaClient = SefariaClient()) { self.client = client }

    public func suggestWords(prefix: String, context: TorahLexicalContext?) async throws -> [WordCandidate] {
        try await resolveWord(surface: prefix, context: context).map(\.candidate)
    }

    public func resolveWord(surface: String, context: TorahLexicalContext?) async throws -> [ResolvedWord] {
        var query: [URLQueryItem] = []
        if let reference = context?.canonicalReference { query.append(URLQueryItem(name: "lookup_ref", value: reference)) }
        let (data, response) = try await client.get(pathSegments: ["api", "words", surface], query: query)
        guard response.statusCode == 200 else { throw TorahError.noResults }
        let object = try jsonObject(data)
        let rows: [[String: Any]]
        if let direct = object as? [[String: Any]] { rows = direct }
        else if let root = object as? [String: Any] {
            rows = (root["results"] as? [[String: Any]]) ?? (root["entries"] as? [[String: Any]]) ?? []
        } else { throw TorahError.malformedResponse }
        let results = rows.enumerated().compactMap { index, row -> ResolvedWord? in
            guard let headword = firstString(row, keys: ["headword", "head_word", "word"]) else { return nil }
            let lexicon = firstString(row, keys: ["parent_lexicon", "lexicon", "lexiconName"]) ?? "Sefaria Lexicon"
            let discriminator = firstString(row, keys: ["rid", "id", "entry_number"]) ?? String(index)
            let key = [lexicon, headword, discriminator].map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "he")) }.joined(separator: "|")
            let description = firstString(row, keys: ["definition", "content", "description"])
            return ResolvedWord(candidate: WordCandidate(id: key, surface: surface, headword: headword, lexicon: lexicon, description: description, payload: jsonString(row)))
        }
        guard !results.isEmpty else { throw TorahError.noResults }
        return results
    }
}
