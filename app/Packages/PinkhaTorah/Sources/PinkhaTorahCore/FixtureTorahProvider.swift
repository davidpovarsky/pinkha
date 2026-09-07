import Foundation

public struct FixtureTorahProvider: ReferenceProvider, TopicProvider, LexicalProvider {
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
            return ResolvedReference(canonical: "Genesis 1:1", labelHe: "בראשית א׳:א׳", labelEn: "Genesis 1:1", payload: #"{"ref":"Genesis 1:1","heRef":"בראשית א׳:א׳"}"#)
        case "Rosh Hashanah 16b":
            return ResolvedReference(canonical: "Rosh Hashanah 16b", labelHe: "ראש השנה ט״ז ב׳", labelEn: "Rosh Hashanah 16b", payload: #"{"ref":"Rosh Hashanah 16b","heRef":"ראש השנה ט״ז ב׳"}"#)
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
}
