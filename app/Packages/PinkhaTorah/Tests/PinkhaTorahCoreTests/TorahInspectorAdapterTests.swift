import Foundation
import Testing
@testable import PinkhaTorahCore

private struct PinkhaInspectorAdapterFixture: TextProvider, RelationshipProvider {
    let providerID = "pinkha-adapter-fixture"

    func fetchText(reference: String, request: TorahTextRequest) async throws -> TorahTextDocument {
        TorahTextDocument(
            providerID: providerID,
            requestedRef: reference,
            canonicalRef: reference,
            sectionRef: reference,
            segments: [TorahTextSegment(canonicalRef: "\(reference):1", text: "בראשית", ordinal: 1)],
            version: TorahTextVersionMetadata(language: "he", versionTitle: "Fixture", direction: "rtl")
        )
    }

    func links(for reference: String) async throws -> [TorahLinkedSource] {
        [TorahLinkedSource(sourceRef: "Rashi on \(reference)", category: "Commentary", type: "commentary")]
    }

    func topics(for reference: String) async throws -> [TorahLinkedTopic] {
        [TorahLinkedTopic(slug: "creation", titleHe: "בריאה")]
    }
}

@Suite("Pinkha shared Inspector adapter")
struct TorahInspectorAdapterTests {
    @Test @MainActor func workspaceBackedRepositoryPreservesProviderData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = PinkhaInspectorAdapterFixture()
        let registry = TorahProviderRegistry(
            referenceProviders: [],
            topicProviders: [],
            lexicalProviders: [],
            textProviders: [fixture],
            relationshipProviders: [fixture],
            defaultProviderID: fixture.providerID
        )
        let workspace = TorahWorkspace(
            store: try TorahStore(databasePath: directory.appendingPathComponent("pinkha.db").path),
            registry: registry
        )
        let repository = TorahInspectorRepository(workspace: workspace)

        #expect(try await repository.document(for: "Genesis 1", providerID: fixture.providerID).segments.first?.text == "בראשית")
        #expect(try await repository.links(for: "Genesis 1:1", providerID: fixture.providerID).first?.category == "Commentary")
        #expect(try await repository.topics(for: "Genesis 1:1", providerID: fixture.providerID).first?.slug == "creation")
    }
}
