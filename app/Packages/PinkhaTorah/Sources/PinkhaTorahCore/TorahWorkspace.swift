import Foundation
import Observation

@MainActor @Observable
public final class TorahWorkspace {
    private let store: TorahStore
    private let registry: TorahProviderRegistry

    public init(store: TorahStore, registry: TorahProviderRegistry) {
        self.store = store; self.registry = registry
    }

    public static func application(databasePath: String, arguments: [String] = ProcessInfo.processInfo.arguments) throws -> TorahWorkspace {
        let store = try TorahStore(databasePath: databasePath)
        if arguments.contains("--ui-test-torah-provider") {
            let provider = FixtureTorahProvider()
            return TorahWorkspace(store: store, registry: TorahProviderRegistry(
                referenceProviders: [provider], topicProviders: [provider], lexicalProviders: [provider],
                defaultProviderID: provider.providerID
            ))
        }
        let client = SefariaClient()
        let reference = SefariaReferenceProvider(client: client)
        let topic = SefariaTopicProvider(client: client, store: store)
        let lexical = SefariaLexicalProvider(client: client)
        return TorahWorkspace(store: store, registry: TorahProviderRegistry(
            referenceProviders: [reference], topicProviders: [topic], lexicalProviders: [lexical], defaultProviderID: "sefaria"
        ))
    }

    public func associations(for target: TorahTarget) async throws -> [TorahAssociation] {
        try await store.associations(for: target)
    }

    public func add(_ association: TorahAssociation, to target: TorahTarget) async throws {
        let value = TorahAssociation(
            id: association.id, target: target, kind: association.kind,
            providerID: association.providerID, externalID: association.externalID,
            canonicalKey: association.canonicalKey, labelHe: association.labelHe,
            labelEn: association.labelEn, rawInput: association.rawInput,
            providerPayload: association.providerPayload,
            createdAt: association.createdAt, updatedAt: association.updatedAt
        )
        try await store.add(value)
    }

    public func remove(associationID: String) async throws { try await store.remove(id: associationID) }

    public func suggestReferences(_ query: String, limit: Int = 12) async throws -> [ReferenceCandidate] {
        try await registry.reference().suggestReferences(query: query, limit: limit)
    }
    public func resolveReference(_ input: String) async throws -> ResolvedReference {
        try await registry.reference().resolveReference(input)
    }
    public func suggestTopics(_ query: String, limit: Int = 20) async throws -> [TopicCandidate] {
        try await registry.topic().suggestTopics(query: query, limit: limit)
    }
    public func resolveTopic(_ id: String) async throws -> ResolvedTopic { try await registry.topic().resolveTopic(id: id) }
    public func refreshTopicIndexIfNeeded() async throws { try await registry.topic().refreshTopicIndexIfNeeded() }
    public func suggestWords(_ query: String, context: TorahLexicalContext?) async throws -> [WordCandidate] {
        try await registry.lexical().suggestWords(prefix: query, context: context)
    }
    public func resolveWord(_ surface: String, context: TorahLexicalContext?) async throws -> [ResolvedWord] {
        try await registry.lexical().resolveWord(surface: surface, context: context)
    }

    public func addReference(_ resolved: ResolvedReference, rawInput: String, to target: TorahTarget) async throws {
        let provider = try registry.reference().providerID
        try await store.add(TorahAssociation(target: target, kind: .ref, providerID: provider,
            externalID: resolved.canonical, canonicalKey: resolved.canonical,
            labelHe: resolved.labelHe, labelEn: resolved.labelEn, rawInput: rawInput,
            providerPayload: resolved.payload))
    }
    public func addTopic(_ resolved: ResolvedTopic, to target: TorahTarget) async throws {
        let provider = try registry.topic().providerID
        try await store.add(TorahAssociation(target: target, kind: .topic, providerID: provider,
            externalID: resolved.slug, canonicalKey: resolved.slug, labelHe: resolved.labelHe,
            labelEn: resolved.labelEn, providerPayload: resolved.payload))
    }
    public func addWord(_ resolved: ResolvedWord, to target: TorahTarget) async throws {
        let provider = try registry.lexical().providerID
        let word = resolved.candidate
        try await store.add(TorahAssociation(target: target, kind: .word, providerID: provider,
            externalID: word.id, canonicalKey: word.id, labelHe: word.surface,
            labelEn: word.headword, rawInput: word.surface, providerPayload: word.payload))
    }

    public func lexicalContext(for target: TorahTarget) async throws -> TorahLexicalContext? {
        let reference = try await store.associations(for: target).first(where: { $0.kind == .ref })
        return reference.map { TorahLexicalContext(canonicalReference: $0.canonicalKey) }
    }
}
