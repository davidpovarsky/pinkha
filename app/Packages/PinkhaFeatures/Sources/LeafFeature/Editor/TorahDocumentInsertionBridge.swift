import Foundation
import Observation
import PinkhaTorahCore
import PinkhaTorahUI

public struct TorahDocumentInsertionAnchor: Sendable, Equatable {
    public let leafId: String
    public let blockId: String?

    public init(leafId: String, blockId: String? = nil) {
        self.leafId = leafId
        self.blockId = blockId
    }
}

/// A document-scoped session representing the active Leaf's Torah Inspector state and actions.
/// Owned strictly by LeafView; published to the presentation host while the document is active.
@MainActor @Observable
public final class TorahDocumentInsertionBridge {
    public let leafId: String
    public let coordinator: TorahInspectorCoordinator
    public var databasePath: String?
    public var activeAnchor: TorahDocumentInsertionAnchor?
    public var onInsert: ((TorahSourceTransfer, TorahDocumentInsertionAnchor?) async throws -> Void)?

    public init(
        leafId: String = "",
        coordinator: TorahInspectorCoordinator = TorahInspectorCoordinator(),
        databasePath: String? = nil,
        activeAnchor: TorahDocumentInsertionAnchor? = nil
    ) {
        self.leafId = leafId
        self.coordinator = coordinator
        self.databasePath = databasePath
        self.activeAnchor = activeAnchor
    }

    public var isPresented: Bool {
        coordinator.isPresented
    }

    public var selection: TorahInspectorSelection? {
        coordinator.selection
    }

    public func close() {
        coordinator.close()
    }

    public func insert(_ transfer: TorahSourceTransfer) async throws {
        guard let onInsert else { return }
        try await onInsert(transfer, activeAnchor)
    }
}

/// Host coordinator held by the stable navigation container (LibraryView).
/// Holds weak references to document-scoped sessions.
/// The host owns NO persistent coordinator, NO selection, and NO document insertion logic.
@MainActor @Observable
public final class TorahInspectorHost {
    private struct WeakSession {
        weak var value: TorahDocumentInsertionBridge?
    }

    private var sessions: [String: WeakSession] = [:]
    public private(set) var activeLeafId: String?

    public init() {}

    public var activeSession: TorahDocumentInsertionBridge? {
        guard let activeLeafId else { return nil }
        return sessions[activeLeafId]?.value
    }

    public func register(session: TorahDocumentInsertionBridge) {
        sessions[session.leafId] = WeakSession(value: session)
        activeLeafId = session.leafId
    }

    public func setActiveLeafId(_ leafId: String?) {
        activeLeafId = leafId
    }

    public func prune(keepingLeafIds leafIds: Set<String>) {
        for (id, weakSession) in sessions where !leafIds.contains(id) {
            weakSession.value?.close()
            sessions.removeValue(forKey: id)
        }
        if let currentActive = activeLeafId, !leafIds.contains(currentActive) {
            activeLeafId = nil
        }
    }

    public func clearAll() {
        for weakSession in sessions.values {
            weakSession.value?.close()
        }
        sessions.removeAll()
        activeLeafId = nil
    }
}
