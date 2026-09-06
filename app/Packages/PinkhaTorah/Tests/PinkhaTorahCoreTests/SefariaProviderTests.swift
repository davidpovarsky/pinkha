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
        let transport = MockTransport(payload: #"{"completion_objects":[{"title":"ברכות ב ע״א"}]}"#)
        let provider = SefariaReferenceProvider(client: SefariaClient(transport: transport))
        let values = try await provider.suggestReferences(query: "ברכות ב ע״א–ע״ב", limit: 7)
        #expect(values.first?.label == "ברכות ב ע״א")
        let url = await transport.lastURL?.absoluteString ?? ""
        #expect(url.contains("type=ref")); #expect(url.contains("limit=7")); #expect(!url.contains(" "))
    }

    @Test func referenceValidationAcceptsCanonicalAndRejectsInvalidShapes() async throws {
        let valid = MockTransport(payload: #"{"is_ref":true,"ref":"Genesis 1:1","heRef":"בראשית א׳:א׳"}"#)
        let resolved = try await SefariaReferenceProvider(client: SefariaClient(transport: valid)).resolveReference("בראשית א:א")
        #expect(resolved.canonical == "Genesis 1:1")
        let invalid = MockTransport(payload: #"{"is_ref":false}"#)
        await #expect(throws: TorahError.invalidReference) { try await SefariaReferenceProvider(client: SefariaClient(transport: invalid)).resolveReference("invalid") }
        let missing = MockTransport(status: 404, payload: #"{"error":"not found"}"#)
        await #expect(throws: TorahError.invalidReference) { try await SefariaReferenceProvider(client: SefariaClient(transport: missing)).resolveReference("invalid") }
    }

    @Test func inflectedWordPreservesSurfaceAndAmbiguity() async throws {
        let payload = #"[{"headword":"שַׁעַר","parent_lexicon":"BDB","rid":"1"},{"headword":"שַׁעַר","parent_lexicon":"Jastrow","rid":"2"}]"#
        let provider = SefariaLexicalProvider(client: SefariaClient(transport: MockTransport(payload: payload)))
        let values = try await provider.resolveWord(surface: "בשעריך", context: TorahLexicalContext(canonicalReference: "Deuteronomy 6:9"))
        #expect(values.count == 2); #expect(values.allSatisfy { $0.candidate.surface == "בשעריך" })
        #expect(Set(values.map { $0.candidate.lexicon }) == ["BDB", "Jastrow"])
    }
}
