import Foundation
import Observation
import PinkhaTorahCore

public struct TorahDocumentInsertionAnchor: Sendable, Equatable {
    public let leafId: String
    public let blockId: String?

    public init(leafId: String, blockId: String? = nil) {
        self.leafId = leafId
        self.blockId = blockId
    }
}

@MainActor @Observable
public final class TorahDocumentInsertionBridge {
    public var activeAnchor: TorahDocumentInsertionAnchor?
    public var onInsert: ((TorahSourceTransfer, TorahDocumentInsertionAnchor?) async throws -> Void)?

    public init(activeAnchor: TorahDocumentInsertionAnchor? = nil) {
        self.activeAnchor = activeAnchor
    }

    public func insert(_ transfer: TorahSourceTransfer) async throws {
        guard let onInsert else { return }
        try await onInsert(transfer, activeAnchor)
    }
}
