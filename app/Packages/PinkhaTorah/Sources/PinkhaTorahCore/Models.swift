import Foundation

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

public struct TorahTextRequest: Hashable, Sendable {
    public var language: String
    public var fillInMissingSegments: Bool
    public init(language: String = "hebrew", fillInMissingSegments: Bool = true) {
        self.language = language
        self.fillInMissingSegments = fillInMissingSegments
    }
}

public struct TorahTextVersionMetadata: Hashable, Codable, Sendable {
    public let language: String
    public let actualLanguage: String?
    public let languageFamilyName: String?
    public let versionTitle: String
    public let versionTitleInHebrew: String?
    public let license: String?
    public let direction: String?
}

public struct TorahTextSegment: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let canonicalRef: String
    public let hebrewRef: String?
    public let text: String
    public let ordinal: Int
    public init(canonicalRef: String, hebrewRef: String? = nil, text: String, ordinal: Int) {
        self.id = canonicalRef; self.canonicalRef = canonicalRef; self.hebrewRef = hebrewRef
        self.text = text; self.ordinal = ordinal
    }
}

public struct TorahTextDocument: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(providerID):\(canonicalRef)" }
    public let providerID: String
    public let requestedRef: String
    public let canonicalRef: String
    public let hebrewRef: String?
    public let sectionRef: String
    public let hebrewSectionRef: String?
    public let segments: [TorahTextSegment]
    public let previousSectionRef: String?
    public let nextSectionRef: String?
    public let version: TorahTextVersionMetadata
    public let rawProviderPayload: String
}

public struct TorahLinkedSource: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(sourceRef)|\(type)|\(category)" }
    public let sourceRef: String
    public let sourceHebrewRef: String?
    public let category: String
    public let type: String
    public let collectiveTitle: String?
    public let hebrewCollectiveTitle: String?
    public let hebrewText: String?
    public let englishText: String?
    public let versionTitle: String?
    public let hebrewVersionTitle: String?
    public let license: String?
    public let rawProviderPayload: String
}

public struct TorahLinkedTopic: Identifiable, Hashable, Codable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let titleHe: String?
    public let titleEn: String?
    public let rawProviderPayload: String
}

public struct TorahInspectorSelection: Identifiable, Hashable, Sendable {
    public var id: String { "\(providerID):\(canonicalRef):\(preferredSegmentRef ?? "")" }
    public let providerID: String
    public let canonicalRef: String
    public let preferredSegmentRef: String?
    public init(providerID: String, canonicalRef: String, preferredSegmentRef: String? = nil) {
        self.providerID = providerID; self.canonicalRef = canonicalRef
        self.preferredSegmentRef = preferredSegmentRef
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

public enum TorahError: LocalizedError, Equatable {
    case invalidReference, referenceTooBroad, missingProvider, noResults, noText, malformedResponse, storage(String), network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReference: "The reference is not valid."
        case .referenceTooBroad: "Choose a more specific source."
        case .missingProvider: "No Torah provider is available."
        case .noResults: "No matching result was found."
        case .noText: "No text is available for this source."
        case .malformedResponse: "The provider returned an unexpected response."
        case .storage(let message), .network(let message): message
        }
    }
}
