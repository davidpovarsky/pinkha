import Foundation

public protocol ReferenceProvider: Sendable {
    var providerID: String { get }
    func suggestReferences(query: String, limit: Int) async throws -> [ReferenceCandidate]
    func resolveReference(_ input: String) async throws -> ResolvedReference
}

public protocol TopicProvider: Sendable {
    var providerID: String { get }
    func suggestTopics(query: String, limit: Int) async throws -> [TopicCandidate]
    func resolveTopic(id: String) async throws -> ResolvedTopic
    func refreshTopicIndexIfNeeded() async throws
}

public protocol LexicalProvider: Sendable {
    var providerID: String { get }
    func suggestWords(prefix: String, context: TorahLexicalContext?) async throws -> [WordCandidate]
    func resolveWord(surface: String, context: TorahLexicalContext?) async throws -> [ResolvedWord]
}

public struct TorahProviderRegistry: Sendable {
    private let references: [String: any ReferenceProvider]
    private let topics: [String: any TopicProvider]
    private let lexicons: [String: any LexicalProvider]
    public let defaultProviderID: String

    public init(
        referenceProviders: [any ReferenceProvider],
        topicProviders: [any TopicProvider],
        lexicalProviders: [any LexicalProvider],
        defaultProviderID: String
    ) {
        self.references = Dictionary(uniqueKeysWithValues: referenceProviders.map { ($0.providerID, $0) })
        self.topics = Dictionary(uniqueKeysWithValues: topicProviders.map { ($0.providerID, $0) })
        self.lexicons = Dictionary(uniqueKeysWithValues: lexicalProviders.map { ($0.providerID, $0) })
        self.defaultProviderID = defaultProviderID
    }

    public func reference(_ id: String? = nil) throws -> any ReferenceProvider {
        guard let value = references[id ?? defaultProviderID] else { throw TorahError.missingProvider }
        return value
    }
    public func topic(_ id: String? = nil) throws -> any TopicProvider {
        guard let value = topics[id ?? defaultProviderID] else { throw TorahError.missingProvider }
        return value
    }
    public func lexical(_ id: String? = nil) throws -> any LexicalProvider {
        guard let value = lexicons[id ?? defaultProviderID] else { throw TorahError.missingProvider }
        return value
    }
}
