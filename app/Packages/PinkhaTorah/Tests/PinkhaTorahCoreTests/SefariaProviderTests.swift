import Foundation
import Testing
@testable import PinkhaTorahCore

private actor MockTransport: TorahHTTPTransport {
    let status: Int; let payload: String
    private(set) var lastURL: URL?
    init(status: Int = 200, payload: String) { self.status = status; self.payload = payload }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastURL = request.url
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private struct AlternateProvider: ReferenceProvider {
    let providerID = "otzaria-test"
    func suggestReferences(query: String, limit: Int) async throws -> [ReferenceCandidate] { [] }
    func resolveReference(_ input: String) async throws -> ResolvedReference { .init(canonical: input, labelHe: input) }
}

@Suite("Sefaria providers")
struct SefariaProviderTests {
    @Test func registrySupportsAnAdditiveSecondProvider() throws {
        let fixture = FixtureTorahProvider()
        let registry = TorahProviderRegistry(referenceProviders: [fixture, AlternateProvider()], topicProviders: [fixture], lexicalProviders: [fixture], defaultProviderID: fixture.providerID)
        #expect(try registry.reference("otzaria-test").providerID == "otzaria-test")
    }

    @Test func referenceSuggestionEncodesHebrewPunctuationAndRange() async throws {
        let transport = MockTransport(payload: #"{"completion_objects":[{"title":"ברכות ב ע״א","key":"Berakhot 2a"}]}"#)
        let provider = SefariaReferenceProvider(client: SefariaClient(transport: transport))
        let values = try await provider.suggestReferences(query: "ברכות ב ע״א–ע״ב", limit: 7)
        #expect(values.first?.label == "ברכות ב ע״א")
        #expect(values.first?.id == "Berakhot 2a")
        let url = await transport.lastURL?.absoluteString ?? ""
        #expect(url.contains("type=ref")); #expect(url.contains("limit=7")); #expect(!url.contains(" "))
    }

    @Test func referenceSuggestionKeepsDisplayTitleSeparateFromResolutionKey() async throws {
        let transport = MockTransport(payload: #"{"completion_objects":[{"title":"ראש השנה ט״ז ב׳","key":"Rosh Hashanah 16b","type":"ref"},{"title":"חסר מפתח","type":"ref"}]}"#)
        let provider = SefariaReferenceProvider(client: SefariaClient(transport: transport))

        let values = try await provider.suggestReferences(query: "ראש הש", limit: 12)

        #expect(values == [ReferenceCandidate(id: "Rosh Hashanah 16b", label: "ראש השנה ט״ז ב׳")])
    }

    @Test func selectedReferenceResolvesWithProviderKeyInsteadOfTitleOrPartialQuery() async throws {
        let completionTransport = MockTransport(payload: #"{"completion_objects":[{"title":"ראש השנה ט״ז ב׳","key":"Rosh Hashanah 16b","type":"ref"}]}"#)
        let candidates = try await SefariaReferenceProvider(client: SefariaClient(transport: completionTransport))
            .suggestReferences(query: "ראש הש", limit: 12)
        let resolutionTransport = MockTransport(payload: #"{"is_ref":true,"normalized":"Rosh Hashanah 16b","hebrew":"ראש השנה ט״ז ב׳","url_ref":"Rosh_Hashanah.16b"}"#)
        let provider = SefariaReferenceProvider(client: SefariaClient(transport: resolutionTransport))

        let resolved = try await provider.resolveReference(candidates[0].id)

        #expect(resolved.canonical == "Rosh Hashanah 16b")
        #expect(resolved.urlRef == "Rosh_Hashanah.16b")
        let url = await resolutionTransport.lastURL?.absoluteString ?? ""
        #expect(url.contains("Rosh%20Hashanah%2016b"))
        #expect(!url.contains("%D7%A8%D7%90%D7%A9"))
    }

    @Test func fixtureRejectsPartialQueryAndDisplayTitle() async throws {
        let provider = FixtureTorahProvider()
        let candidate = try await provider.suggestReferences(query: "ראש הש", limit: 12)[0]
        #expect(candidate.id == "Rosh Hashanah 16b")
        #expect(candidate.label == "ראש השנה ט״ז ב׳")
        #expect(try await provider.resolveReference(candidate.id).canonical == "Rosh Hashanah 16b")
        await #expect(throws: TorahError.invalidReference) { try await provider.resolveReference("ראש הש") }
        await #expect(throws: TorahError.invalidReference) { try await provider.resolveReference(candidate.label) }
    }

    @Test func referenceValidationAcceptsCanonicalAndRejectsInvalidShapes() async throws {
        let valid = MockTransport(payload: #"{"is_ref":true,"normalized":"Genesis 1:1","hebrew":"בראשית א׳:א׳","url_ref":"Genesis.1.1"}"#)
        let resolved = try await SefariaReferenceProvider(client: SefariaClient(transport: valid)).resolveReference("בראשית א:א")
        #expect(resolved.canonical == "Genesis 1:1")
        let invalid = MockTransport(payload: #"{"is_ref":false}"#)
        await #expect(throws: TorahError.invalidReference) { try await SefariaReferenceProvider(client: SefariaClient(transport: invalid)).resolveReference("invalid") }
        let missing = MockTransport(status: 404, payload: #"{"error":"not found"}"#)
        await #expect(throws: TorahError.invalidReference) { try await SefariaReferenceProvider(client: SefariaClient(transport: missing)).resolveReference("invalid") }
    }

    @Test func normalizedResponseWinsOverCandidateKeyAndDisplayTitle() async throws {
        let completion = MockTransport(payload: #"{"completion_objects":[{"title":"ראש השנה ט״ז ב׳","key":"Rosh Hashanah 16B"}]}"#)
        let candidate = try await SefariaReferenceProvider(client: SefariaClient(transport: completion)).suggestReferences(query: "ראש", limit: 1)[0]
        let resolution = MockTransport(payload: #"{"is_ref":true,"normalized":"Rosh Hashanah 16b","hebrew":"ראש השנה ט״ז ב׳","url_ref":"Rosh_Hashanah.16b"}"#)
        let resolved = try await SefariaReferenceProvider(client: SefariaClient(transport: resolution)).resolveReference(candidate.id)
        #expect(candidate.label != candidate.id)
        #expect(candidate.id != resolved.canonical)
        #expect(resolved.canonical == "Rosh Hashanah 16b")
    }

    @Test func textsV3DecodesSectionSegmentsNavigationAndProvenance() throws {
        let root: [String: Any] = [
            "ref": "Genesis 1", "heRef": "בראשית א׳", "sectionRef": "Genesis 1", "heSectionRef": "בראשית א׳",
            "versions": [["language": "he", "actualLanguage": "he", "languageFamilyName": "hebrew", "versionTitle": "Test Hebrew", "versionTitleInHebrew": "נוסח בדיקה", "license": "CC-BY", "direction": "rtl", "text": ["א", "ב", "ג"]]]
        ]
        let metadata: [String: Any] = ["is_ref": true, "depth": 2, "start_indexes": [0], "navigation_refs": ["prev_section_ref": "Genesis 0", "next_section_ref": "Genesis 2"]]
        let value = try SefariaTextProvider.decode(reference: "Genesis 1", root: root, metadata: metadata)
        #expect(value.segments.map(\.canonicalRef) == ["Genesis 1:1", "Genesis 1:2", "Genesis 1:3"])
        #expect(value.previousSectionRef == "Genesis 0"); #expect(value.nextSectionRef == "Genesis 2")
        #expect(value.version.versionTitle == "Test Hebrew"); #expect(value.version.license == "CC-BY")
    }

    @Test func textsV3DecodesTalmudPageAndExactSegment() throws {
        let page: [String: Any] = ["ref": "Berakhot 2a", "sectionRef": "Berakhot 2a", "versions": [["language": "he", "versionTitle": "Vilna", "text": ["א", "ב"]]]]
        let pageMeta: [String: Any] = ["depth": 2, "start_indexes": [1], "navigation_refs": ["next_section_ref": "Berakhot 2b"]]
        #expect(try SefariaTextProvider.decode(reference: "Berakhot 2a", root: page, metadata: pageMeta).segments.map(\.canonicalRef) == ["Berakhot 2a:1", "Berakhot 2a:2"])
        let segment: [String: Any] = ["ref": "Genesis 1:7", "heRef": "בראשית א׳:ז׳", "sectionRef": "Genesis 1", "versions": [["language": "he", "versionTitle": "Test", "text": "פסוק"]]]
        let segmentMeta: [String: Any] = ["depth": 2, "start_indexes": [0, 6], "navigation_refs": [:]]
        #expect(try SefariaTextProvider.decode(reference: "Genesis 1:7", root: segment, metadata: segmentMeta).segments[0].canonicalRef == "Genesis 1:7")
    }

    @Test func linksAndTopicsPreserveRelationshipKinds() async throws {
        let linksPayload = #"[{"sourceRef":"Rashi on Genesis 1:1:1","sourceHeRef":"רש״י","category":"Commentary","type":"commentary","collectiveTitle":{"en":"Rashi","he":"רש״י"},"he":"פירוש","heVersionTitle":"מקראות","heLicense":"CC-BY-SA"},{"sourceRef":"Midrash Rabbah 1:1","category":"Midrash","type":"midrash","he":"מדרש"}]"#
        let links = try await SefariaRelationshipProvider(client: SefariaClient(transport: MockTransport(payload: linksPayload))).links(for: "Genesis 1:1")
        #expect(links[0].category == "Commentary"); #expect(links[0].hebrewCollectiveTitle == "רש״י")
        #expect(links[1].category == "Midrash")
        let topicsPayload = #"[{"topic":"creation","descriptions":{"en":{"title":"Creation"},"he":{"title":"בריאה"}}},{"topic":"creation"}]"#
        let transport = MockTransport(payload: topicsPayload)
        let topics = try await SefariaRelationshipProvider(client: SefariaClient(transport: transport)).topics(for: "Genesis 1:1")
        #expect(topics.count == 1); #expect(topics[0].slug == "creation"); #expect(topics[0].titleHe == "בריאה")
        let topicsURL = await transport.lastURL?.absoluteString ?? ""
        #expect(topicsURL.contains("interface_lang=english"))
    }

    @Test func inflectedWordPreservesSurfaceAndAmbiguity() async throws {
        let payload = #"[{"headword":"שַׁעַר","parent_lexicon":"BDB","rid":"1"},{"headword":"שַׁעַר","parent_lexicon":"Jastrow","rid":"2"}]"#
        let provider = SefariaLexicalProvider(client: SefariaClient(transport: MockTransport(payload: payload)))
        let values = try await provider.resolveWord(surface: "בשעריך", context: TorahLexicalContext(canonicalReference: "Deuteronomy 6:9"))
        #expect(values.count == 2); #expect(values.allSatisfy { $0.candidate.surface == "בשעריך" })
        #expect(Set(values.map { $0.candidate.lexicon }) == ["BDB", "Jastrow"])
    }
}
