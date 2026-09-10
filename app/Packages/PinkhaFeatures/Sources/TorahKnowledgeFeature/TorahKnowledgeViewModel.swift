import Foundation
import Observation
import PinkhaTorahCore

/// View model for the Torah Knowledge tab.
/// Manages the three segments (מקור / מילה / נושא) and provides
/// filtered, compressed hierarchy data for the source segment
/// and grouped association data for word and topic segments.
@MainActor @Observable
public final class TorahKnowledgeViewModel {
    // MARK: - Public state

    public enum Segment: String, CaseIterable, Identifiable, Sendable {
        case source = "מקור"
        case word = "מילה"
        case topic = "נושא"
        public var id: String { rawValue }
    }

    public var selectedSegment: Segment = .source

    /// Source hierarchy filtered to only branches with user associations.
    public private(set) var filteredHierarchy: TorahSourceHierarchy?
    /// Current navigation path through the hierarchy.
    public var hierarchyPath: [TorahSourceNode] = []

    /// Word association groups: (canonicalKey, labelHe, leafCount).
    public private(set) var wordGroups: [(canonicalKey: String, labelHe: String, leafCount: Int)] = []
    /// Topic association groups.
    public private(set) var topicGroups: [(canonicalKey: String, labelHe: String, leafCount: Int)] = []

    /// Leaf IDs for the currently selected association key.
    public private(set) var selectedLeafIDs: [String] = []
    /// The currently selected association key (for drill-in).
    public var selectedKey: String?

    /// Loading / error state.
    public private(set) var isLoading = false
    public var errorMessage: String?

    // MARK: - Dependencies

    private let databasePath: String
    private var workspace: TorahWorkspace?
    private var hierarchyProvider: (any TorahHierarchyProvider)?

    public init(databasePath: String) {
        self.databasePath = databasePath
    }

    // MARK: - Loading

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let ws = try TorahWorkspace.application(databasePath: databasePath)
            workspace = ws

            // Load all segments in parallel
            async let sourceTask: () = loadSourceHierarchy(workspace: ws)
            async let wordTask: () = loadWordGroups(workspace: ws)
            async let topicTask: () = loadTopicGroups(workspace: ws)

            _ = try await (sourceTask, wordTask, topicTask)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSourceHierarchy(workspace: TorahWorkspace) async throws {
        let store = try TorahStore(databasePath: databasePath)
        let provider = SefariaHierarchyProvider(store: store)
        hierarchyProvider = provider

        // Fetch the full Sefaria hierarchy (cached)
        let fullHierarchy = try await provider.fetchHierarchy()

        // Get user's source associations to filter the hierarchy
        let sourceGroups = try await workspace.distinctAssociationGroups(kind: .ref)
        let associatedKeys = Set(sourceGroups.map(\.canonicalKey))

        // Filter hierarchy to only show branches with user associations
        filteredHierarchy = fullHierarchy.filtered(byAssociatedKeys: associatedKeys)
    }

    private func loadWordGroups(workspace: TorahWorkspace) async throws {
        wordGroups = try await workspace.distinctAssociationGroups(kind: .word)
    }

    private func loadTopicGroups(workspace: TorahWorkspace) async throws {
        topicGroups = try await workspace.distinctAssociationGroups(kind: .topic)
    }

    // MARK: - Drill-in

    /// Load leaf IDs for a specific association key.
    public func loadLeafIDs(forKey key: String, kind: TorahAssociationKind) async {
        selectedKey = key
        do {
            guard let workspace else { return }
            selectedLeafIDs = try await workspace.leafIDs(forCanonicalKey: key, kind: kind)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The nodes to display at the current hierarchy level.
    public var currentHierarchyNodes: [TorahSourceNode] {
        if let lastNode = hierarchyPath.last {
            return lastNode.compressedChildren
        }
        return filteredHierarchy?.roots.compactMap { root in
            let compressed = root.compressedTarget
            return compressed.descendantLeafCount > 0 || compressed.hasDirectLeaves ? compressed : nil
        } ?? []
    }

    /// Navigate into a hierarchy node.
    public func navigateInto(_ node: TorahSourceNode) {
        // Auto-compress: if the node has a single child chain, jump to the target
        let target = node.compressedTarget
        hierarchyPath.append(target)
    }

    /// Navigate back one level.
    public func navigateBack() {
        if !hierarchyPath.isEmpty { hierarchyPath.removeLast() }
    }

    /// Navigate to root.
    public func navigateToRoot() {
        hierarchyPath.removeAll()
    }
}
