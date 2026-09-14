import Foundation
import TorahInspectorCore

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
        if reference == "Genesis 2" {
            return TorahTextDocument(
                providerID: providerID,
                requestedRef: reference,
                canonicalRef: "Genesis 2",
                hebrewRef: "בראשית ב׳",
                sectionRef: "Genesis 2",
                hebrewSectionRef: "בראשית ב׳",
                segments: [
                    TorahTextSegment(canonicalRef: "Genesis 2:1", hebrewRef: "בראשית ב׳:א׳", text: "וַיְכֻלּוּ הַשָּׁמַיִם וְהָאָרֶץ וְכָל־צְבָאָם׃", ordinal: 1),
                    TorahTextSegment(canonicalRef: "Genesis 2:2", hebrewRef: "בראשית ב׳:ב׳", text: "וַיְכַל אֱלֹהִים בַּיּוֹם הַשְּׁבִיעִי מְלַאכְתּוֹ אֲשֶׁר עָשָׂה", ordinal: 2)
                ],
                previousSectionRef: "Genesis 1",
                nextSectionRef: "Genesis 3",
                version: TorahTextVersionMetadata(language: "he", actualLanguage: "he", languageFamilyName: "hebrew", versionTitle: "Fixture Hebrew", versionTitleInHebrew: "נוסח בדיקה", license: "CC0", direction: "rtl"),
                rawProviderPayload: #"{"fixture":true}"#
            )
        } else if reference == "Genesis 1" || reference.hasPrefix("Genesis 1:") {
            let directSegment = reference.hasPrefix("Genesis 1:")
            let canonical = directSegment ? reference : "Genesis 1"
            let he = directSegment ? "בראשית א׳:א׳" : "בראשית א׳"
            let segments: [TorahTextSegment]
            if directSegment {
                segments = [
                    TorahTextSegment(canonicalRef: "Genesis 1:1", hebrewRef: "בראשית א׳:א׳", text: "בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ׃", ordinal: 1)
                ]
            } else {
                segments = [
                    TorahTextSegment(canonicalRef: "Genesis 1:1", hebrewRef: "בראשית א׳:א׳", text: "בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ׃", ordinal: 1),
                    TorahTextSegment(canonicalRef: "Genesis 1:2", hebrewRef: "בראשית א׳:ב׳", text: "וְהָאָרֶץ הָיְתָה תֹהוּ וָבֹהוּ וְחֹשֶׁךְ עַל־פְּנֵי תְהוֹם וְרוּחַ אֱלֹהִים מְרַחֶפֶת עַל־פְּנֵי הַמָּיִם׃", ordinal: 2),
                    TorahTextSegment(canonicalRef: "Genesis 1:3", hebrewRef: "בראשית א׳:ג׳", text: "וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי־אוֹר׃", ordinal: 3)
                ]
            }
            return TorahTextDocument(
                providerID: providerID,
                requestedRef: reference,
                canonicalRef: canonical,
                hebrewRef: he,
                sectionRef: "Genesis 1",
                hebrewSectionRef: "בראשית א׳",
                segments: segments,
                previousSectionRef: nil,
                nextSectionRef: "Genesis 2",
                version: TorahTextVersionMetadata(language: "he", actualLanguage: "he", languageFamilyName: "hebrew", versionTitle: "Fixture Hebrew", versionTitleInHebrew: "נוסח בדיקה", license: "CC0", direction: "rtl"),
                rawProviderPayload: #"{"fixture":true}"#
            )
        } else {
            let canonical = reference == "Rosh Hashanah 16b" ? reference : "Genesis 1:1"
            let he = canonical == "Genesis 1:1" ? "בראשית א׳:א׳" : "ראש השנה ט״ז ב׳"
            return TorahTextDocument(
                providerID: providerID, requestedRef: reference, canonicalRef: canonical,
                hebrewRef: he, sectionRef: canonical, hebrewSectionRef: he,
                segments: [
                    TorahTextSegment(canonicalRef: canonical, hebrewRef: he, text: canonical == "Genesis 1:1" ? "בְּרֵאשִׁית בָּרָא אֱלֹהִים" : "ארבעה ראשי שנים הם", ordinal: 1),
                    TorahTextSegment(canonicalRef: canonical == "Genesis 1:1" ? "Genesis 1:2" : "Rosh Hashanah 16b:2", hebrewRef: he, text: canonical == "Genesis 1:1" ? "והארץ היתה תהו ובהו" : "באחד בניסן ראש השנה למלכים", ordinal: 2)
                ],
                previousSectionRef: nil, nextSectionRef: canonical == "Rosh Hashanah 16b" ? "Rosh Hashanah 17a" : "Genesis 2",
                version: TorahTextVersionMetadata(language: "he", actualLanguage: "he", languageFamilyName: "hebrew", versionTitle: "Fixture Hebrew", versionTitleInHebrew: "נוסח בדיקה", license: "CC0", direction: "rtl"),
                rawProviderPayload: #"{"fixture":true}"#
            )
        }
    }
    public func links(for reference: String) async throws -> [TorahLinkedSource] { [] }
    public func topics(for reference: String) async throws -> [TorahLinkedTopic] { [] }
}

public struct FixtureHierarchyProvider: TorahHierarchyProvider {
    public let providerID = "sefaria-fixture"
    public init(store: TorahStore? = nil) {}

    public func fetchHierarchy() async throws -> TorahSourceHierarchy {
        let genesis = TorahSourceNode(
            id: "Genesis",
            labelHe: "בראשית",
            labelEn: "Genesis",
            canonicalKey: "Genesis"
        )
        let roshHashanah = TorahSourceNode(
            id: "Rosh Hashanah",
            labelHe: "ראש השנה",
            labelEn: "Rosh Hashanah",
            canonicalKey: "Rosh Hashanah"
        )
        let torahCategory = TorahSourceNode(
            id: "Torah",
            labelHe: "תורה",
            labelEn: "Torah",
            children: [genesis]
        )
        let talmudCategory = TorahSourceNode(
            id: "Talmud",
            labelHe: "תלמוד",
            labelEn: "Talmud",
            children: [roshHashanah]
        )
        return TorahSourceHierarchy(
            roots: [torahCategory, talmudCategory],
            providerID: providerID
        )
    }
}
