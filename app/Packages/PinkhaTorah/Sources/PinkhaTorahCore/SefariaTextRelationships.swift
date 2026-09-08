import Foundation
import TorahInspectorCore

private func sefariaObject(_ data: Data) throws -> Any {
    do { return try JSONSerialization.jsonObject(with: data) }
    catch { throw TorahError.malformedResponse }
}

private func sefariaPayload(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

private func string(_ object: [String: Any], _ keys: String...) -> String? {
    for key in keys {
        guard let value = object[key] as? String else { continue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return nil
}

private func localized(_ object: Any?) -> (he: String?, en: String?) {
    guard let value = object as? [String: Any] else { return (nil, nil) }
    return (string(value, "he", "hebrew"), string(value, "en", "english"))
}

public struct SefariaTextProvider: TextProvider {
    public let providerID = "sefaria"
    private let client: SefariaClient
    public init(client: SefariaClient = SefariaClient()) { self.client = client }

    public func fetchText(reference: String, request: TorahTextRequest = TorahTextRequest()) async throws -> TorahTextDocument {
        async let metadataCall = client.get(pathSegments: ["api", "ref", reference])
        async let textCall = fetchPayload(reference: reference, version: request.language, fill: request.fillInMissingSegments)
        let ((metadataData, metadataResponse), initialText) = try await (metadataCall, textCall)
        guard metadataResponse.statusCode == 200,
              let metadata = try sefariaObject(metadataData) as? [String: Any],
              metadata["is_ref"] as? Bool == true
        else { throw TorahError.invalidReference }
        var textResult = initialText
        if !Self.hasUsableVersion(textResult.root) && request.language.lowercased() != "source" {
            textResult = try await fetchPayload(reference: reference, version: "source", fill: request.fillInMissingSegments)
        }
        return try Self.decode(reference: reference, root: textResult.root, metadata: metadata)
    }

    private func fetchPayload(reference: String, version: String, fill: Bool) async throws -> (root: [String: Any], payload: String) {
        let (data, response) = try await client.get(pathSegments: ["api", "v3", "texts", reference], query: [
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "fill_in_missing_segments", value: fill ? "1" : "0"),
            URLQueryItem(name: "return_format", value: "text_only")
        ])
        guard response.statusCode == 200, let root = try sefariaObject(data) as? [String: Any] else {
            throw TorahError.network("Sefaria returned HTTP \(response.statusCode).")
        }
        return (root, sefariaPayload(root))
    }

    private static func hasUsableVersion(_ root: [String: Any]) -> Bool {
        (root["versions"] as? [[String: Any]])?.contains { segmentTexts($0["text"]).contains { !$0.text.isEmpty } } == true
    }

    static func decode(reference: String, root: [String: Any], metadata: [String: Any]) throws -> TorahTextDocument {
        guard let canonical = string(root, "ref", "sectionRef"),
              let sectionRef = string(root, "sectionRef", "ref"),
              let versionObject = (root["versions"] as? [[String: Any]])?.first(where: { !segmentTexts($0["text"]).isEmpty }),
              let versionTitle = string(versionObject, "versionTitle"),
              let language = string(versionObject, "language", "actualLanguage")
        else { throw TorahError.noText }
        let texts = segmentTexts(versionObject["text"]).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !texts.isEmpty else { throw TorahError.noText }
        let startIndexes = metadata["start_indexes"] as? [Int] ?? []
        let startOrdinal = (startIndexes.count >= (metadata["depth"] as? Int ?? Int.max)) ? (startIndexes.last ?? 0) + 1 : 1
        let directSegment = texts.count == 1 && startIndexes.count == (metadata["depth"] as? Int ?? -1)
        let segments = texts.map { entry in
            let ordinal = startOrdinal + entry.offset
            let segmentRef = directSegment ? canonical : "\(sectionRef):\(ordinal)"
            return TorahTextSegment(canonicalRef: segmentRef, hebrewRef: directSegment ? string(root, "heRef") : nil, text: entry.text, ordinal: ordinal)
        }
        let navigation = metadata["navigation_refs"] as? [String: Any] ?? [:]
        let version = TorahTextVersionMetadata(
            language: language,
            actualLanguage: string(versionObject, "actualLanguage"),
            languageFamilyName: string(versionObject, "languageFamilyName"),
            versionTitle: versionTitle,
            versionTitleInHebrew: string(versionObject, "versionTitleInHebrew"),
            license: string(versionObject, "license"),
            direction: string(versionObject, "direction")
        )
        return TorahTextDocument(
            providerID: "sefaria", requestedRef: reference, canonicalRef: canonical,
            hebrewRef: string(root, "heRef"), sectionRef: sectionRef,
            hebrewSectionRef: string(root, "heSectionRef"), segments: segments,
            previousSectionRef: string(navigation, "prev_section_ref"),
            nextSectionRef: string(navigation, "next_section_ref"), version: version,
            rawProviderPayload: sefariaPayload(root)
        )
    }

    private static func segmentTexts(_ value: Any?) -> [(offset: Int, text: String)] {
        if let text = value as? String { return [(0, text)] }
        guard let values = value as? [Any] else { return [] }
        return values.enumerated().flatMap { index, value -> [(offset: Int, text: String)] in
            if let text = value as? String { return [(index, text)] }
            return segmentTexts(value).map { (index + $0.offset, $0.text) }
        }
    }
}

public struct SefariaRelationshipProvider: RelationshipProvider {
    public let providerID = "sefaria"
    private let client: SefariaClient
    public init(client: SefariaClient = SefariaClient()) { self.client = client }

    public func links(for reference: String) async throws -> [TorahLinkedSource] {
        let (data, response) = try await client.get(pathSegments: ["api", "links", reference], query: [URLQueryItem(name: "with_text", value: "1")])
        guard response.statusCode == 200, let rows = try sefariaObject(data) as? [[String: Any]] else { throw TorahError.malformedResponse }
        return rows.compactMap { row in
            guard let sourceRef = string(row, "sourceRef", "ref") else { return nil }
            let collective = localized(row["collectiveTitle"])
            return TorahLinkedSource(
                sourceRef: sourceRef, sourceHebrewRef: string(row, "sourceHeRef"),
                category: string(row, "category") ?? "Other", type: string(row, "type") ?? "link",
                collectiveTitle: collective.en, hebrewCollectiveTitle: collective.he,
                hebrewText: string(row, "he"), englishText: string(row, "text"),
                versionTitle: string(row, "versionTitle"), hebrewVersionTitle: string(row, "heVersionTitle"),
                license: string(row, "heLicense", "license"), rawProviderPayload: sefariaPayload(row)
            )
        }
    }

    public func topics(for reference: String) async throws -> [TorahLinkedTopic] {
        let (data, response) = try await client.get(pathSegments: ["api", "ref-topic-links", reference], query: [URLQueryItem(name: "interface_lang", value: "english")])
        guard response.statusCode == 200, let rows = try sefariaObject(data) as? [[String: Any]] else { throw TorahError.malformedResponse }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let slug = string(row, "topic"), seen.insert(slug).inserted else { return nil }
            let descriptions = row["descriptions"] as? [String: Any]
            let en = (descriptions?["en"] as? [String: Any]).flatMap { string($0, "title") }
            let he = (descriptions?["he"] as? [String: Any]).flatMap { string($0, "title") }
            return TorahLinkedTopic(slug: slug, titleHe: he, titleEn: en, rawProviderPayload: sefariaPayload(row))
        }
    }
}
