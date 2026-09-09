import Foundation

public struct FixtureTorahProvider: ReferenceProvider, TopicProvider, LexicalProvider, TextProvider, RelationshipProvider {
    public let providerID = "sefaria-fixture"
    public init() {}
    public func suggestReferences(query: String, limit: Int) async throws -> [ReferenceCandidate] {
        guard !query.isEmpty else { return [] }
        if query.contains("ראש") {
            return [ReferenceCandidate(id: "Rosh Hashanah 16b", label: "ראש השנה ט״ז ב׳")]
        }
        return [ReferenceCandidate(id: "Genesis 1:1", label: "בראשית א׳:א׳ — Genesis 1:1")]
    }
    public func resolveReference(_ input: String) async throws -> ResolvedReference {
        switch input {
        case "Genesis 1:1":
            return ResolvedReference(canonical: "Genesis 1:1", labelHe: "בראשית א׳:א׳", labelEn: "Genesis 1:1", payload: #"{"is_ref":true,"normalized":"Genesis 1:1","hebrew":"בראשית א׳:א׳","url_ref":"Genesis.1.1"}"#, urlRef: "Genesis.1.1", nodeType: "JaggedArrayNode", depth: 2, startIndexes: [0, 0], endIndexes: [0, 0], firstAvailableSectionRef: "Genesis 1")
        case "Rosh Hashanah 16b":
            return ResolvedReference(canonical: "Rosh Hashanah 16b", labelHe: "ראש השנה ט״ז ב׳", labelEn: "Rosh Hashanah 16b", payload: #"{"is_ref":true,"normalized":"Rosh Hashanah 16b","hebrew":"ראש השנה ט״ז ב׳","url_ref":"Rosh_Hashanah.16b"}"#, urlRef: "Rosh_Hashanah.16b", nodeType: "JaggedArrayNode", depth: 2, startIndexes: [31], endIndexes: [31], firstAvailableSectionRef: "Rosh Hashanah 2a")
        default:
            throw TorahError.invalidReference
        }
    }
    public func suggestTopics(query: String, limit: Int) async throws -> [TopicCandidate] {
        query.isEmpty ? [] : [TopicCandidate(id: "prayer", labelHe: "תפילה", labelEn: "Prayer")]
    }
    public func resolveTopic(id: String) async throws -> ResolvedTopic {
        ResolvedTopic(slug: "prayer", labelHe: "תפילה", labelEn: "Prayer", payload: #"{"slug":"prayer"}"#)
    }
    public func refreshTopicIndexIfNeeded() async throws {}
    public func suggestWords(prefix: String, context: TorahLexicalContext?) async throws -> [WordCandidate] {
        try await resolveWord(surface: prefix, context: context).map(\.candidate)
    }
    public func resolveWord(surface: String, context: TorahLexicalContext?) async throws -> [ResolvedWord] {
        guard !surface.isEmpty else { return [] }
        return [
            ResolvedWord(candidate: WordCandidate(id: "BDB|שַׁעַר|1", surface: surface, headword: "שַׁעַר", lexicon: "BDB", description: "gate; entrance", payload: #"{"headword":"שַׁעַר","parent_lexicon":"BDB"}"#)),
            ResolvedWord(candidate: WordCandidate(id: "Jastrow|שַׁעַר|2", surface: surface, headword: "שַׁעַר", lexicon: "Jastrow Dictionary", description: "gate", payload: #"{"headword":"שַׁעַר","parent_lexicon":"Jastrow Dictionary"}"#))
        ]
    }
    public func fetchText(reference: String, request: TorahTextRequest) async throws -> TorahTextDocument {
        let canonical = reference == "Rosh Hashanah 16b" ? reference : "Genesis 1:1"
        let he = canonical == "Genesis 1:1" ? "בראשית א׳:א׳" : "ראש השנה ט״ז ב׳"
        return TorahTextDocument(providerID: providerID, requestedRef: reference, canonicalRef: canonical,
            hebrewRef: he, sectionRef: canonical, hebrewSectionRef: he,
            segments: [TorahTextSegment(canonicalRef: canonical, hebrewRef: he, text: "בְּרֵאשִׁית בָּרָא אֱלֹהִים", ordinal: 1)],
            previousSectionRef: nil, nextSectionRef: nil,
            version: TorahTextVersionMetadata(language: "he", actualLanguage: "he", languageFamilyName: "hebrew", versionTitle: "Fixture Hebrew", versionTitleInHebrew: "נוסח בדיקה", license: "CC0", direction: "rtl"),
            rawProviderPayload: #"{"fixture":true}"#)
    }
    public func links(for reference: String) async throws -> [TorahLinkedSource] { [] }
    public func topics(for reference: String) async throws -> [TorahLinkedTopic] { [] }
}
