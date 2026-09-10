import Foundation
@_exported import TorahInspectorCore

public enum TorahAssociationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ref, topic, word
    public var id: String { rawValue }
}

public enum TorahAssociationRole: String, Codable, CaseIterable, Sendable {
    case context
    case sourceQuote = "source_quote"
}

public enum TorahTarget: Hashable, Codable, Identifiable, Sendable {
    case leaf(String)
    case block(leafID: String, blockID: String)

    public var id: String {
        switch self {
        case .leaf(let leafID): "leaf:\(leafID)"
        case .block(let leafID, let blockID): "block:\(leafID):\(blockID)"
        }
    }

    public var leafID: String {
        switch self {
        case .leaf(let leafID), .block(let leafID, _): leafID
        }
    }

    public var targetID: String {
        switch self {
        case .leaf(let leafID): leafID
        case .block(_, let blockID): blockID
        }
    }

    public var targetKind: String {
        switch self { case .leaf: "leaf"; case .block: "block" }
    }
}

public struct TorahAssociation: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let target: TorahTarget
    public let kind: TorahAssociationKind
    public let role: TorahAssociationRole
    public let providerID: String
    public let externalID: String
    public let canonicalKey: String
    public let labelHe: String
    public let labelEn: String?
    public let rawInput: String?
    public let providerPayload: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        target: TorahTarget,
        kind: TorahAssociationKind,
        role: TorahAssociationRole = .context,
        providerID: String,
        externalID: String,
        canonicalKey: String,
        labelHe: String,
        labelEn: String? = nil,
        rawInput: String? = nil,
        providerPayload: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id; self.target = target; self.kind = kind; self.role = role
        self.providerID = providerID; self.externalID = externalID
        self.canonicalKey = canonicalKey; self.labelHe = labelHe
        self.labelEn = labelEn; self.rawInput = rawInput
        self.providerPayload = providerPayload
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct ReferenceCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct TopicCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let labelHe: String
    public let labelEn: String?
    public init(id: String, labelHe: String, labelEn: String? = nil) {
        self.id = id; self.labelHe = labelHe; self.labelEn = labelEn
    }
}

public struct WordCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let surface: String
    public let headword: String
    public let lexicon: String
    public let description: String?
    public let payload: String
    public init(id: String, surface: String, headword: String, lexicon: String, description: String? = nil, payload: String = "{}") {
        self.id = id; self.surface = surface; self.headword = headword
        self.lexicon = lexicon; self.description = description; self.payload = payload
    }
}

public struct ResolvedReference: Sendable {
    public let canonical: String
    public let labelHe: String
    public let labelEn: String?
    public let payload: String
    public let urlRef: String?
    public let nodeType: String?
    public let depth: Int?
    public let startIndexes: [Int]
    public let endIndexes: [Int]
    public let firstAvailableSectionRef: String?
    public init(canonical: String, labelHe: String, labelEn: String? = nil, payload: String = "{}", urlRef: String? = nil, nodeType: String? = nil, depth: Int? = nil, startIndexes: [Int] = [], endIndexes: [Int] = [], firstAvailableSectionRef: String? = nil) {
        self.canonical = canonical; self.labelHe = labelHe; self.labelEn = labelEn; self.payload = payload
        self.urlRef = urlRef; self.nodeType = nodeType; self.depth = depth
        self.startIndexes = startIndexes; self.endIndexes = endIndexes
        self.firstAvailableSectionRef = firstAvailableSectionRef
    }

    public var isEmbeddableSource: Bool {
        guard nodeType == nil || nodeType == "JaggedArrayNode" else { return false }
        guard let depth else { return true }
        return !startIndexes.isEmpty && startIndexes.count >= max(1, depth - 1)
    }
}

public struct TorahSourceQuoteProvenance: Codable, Sendable {
    public let retrievedAt: Date
    public let canonicalRef: String
    public let referenceProviderPayload: String
    public let textDocument: TorahTextDocument
    public init(retrievedAt: Date = Date(), canonicalRef: String, referenceProviderPayload: String, textDocument: TorahTextDocument) {
        self.retrievedAt = retrievedAt; self.canonicalRef = canonicalRef
        self.referenceProviderPayload = referenceProviderPayload; self.textDocument = textDocument
    }
}

public struct ResolvedTopic: Sendable {
    public let slug: String
    public let labelHe: String
    public let labelEn: String?
    public let payload: String
    public init(slug: String, labelHe: String, labelEn: String? = nil, payload: String = "{}") {
        self.slug = slug; self.labelHe = labelHe; self.labelEn = labelEn; self.payload = payload
    }
}

public struct ResolvedWord: Sendable {
    public let candidate: WordCandidate
    public init(candidate: WordCandidate) { self.candidate = candidate }
}

public struct TorahLexicalContext: Sendable {
    public let canonicalReference: String?
    public init(canonicalReference: String? = nil) { self.canonicalReference = canonicalReference }
}
