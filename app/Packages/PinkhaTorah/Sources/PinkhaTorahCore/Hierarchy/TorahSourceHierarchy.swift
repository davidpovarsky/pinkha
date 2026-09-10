import Foundation

// MARK: - Provider-neutral Torah source hierarchy models

/// A node in a Torah source hierarchy tree.
/// Provider-neutral: Sefaria is the first implementation, Otzaria plugs in later
/// without changing this model.
public struct TorahSourceNode: Identifiable, Hashable, Sendable {
    public let id: String
    /// Hebrew display label for this node.
    public let labelHe: String
    /// Optional English/transliterated label.
    public let labelEn: String?
    /// Canonical key if this node represents a specific Torah reference.
    /// `nil` for category/structural nodes that are pure grouping.
    public let canonicalKey: String?
    /// Child nodes in the hierarchy.
    public var children: [TorahSourceNode]
    /// Number of Pinkha pages reachable under this subtree (direct + descendants).
    public var descendantLeafCount: Int
    /// Whether this node itself has directly associated Pinkha pages.
    public var hasDirectLeaves: Bool

    public init(
        id: String,
        labelHe: String,
        labelEn: String? = nil,
        canonicalKey: String? = nil,
        children: [TorahSourceNode] = [],
        descendantLeafCount: Int = 0,
        hasDirectLeaves: Bool = false
    ) {
        self.id = id; self.labelHe = labelHe; self.labelEn = labelEn
        self.canonicalKey = canonicalKey; self.children = children
        self.descendantLeafCount = descendantLeafCount
        self.hasDirectLeaves = hasDirectLeaves
    }
}

/// A path through the hierarchy, used for breadcrumbs and navigation context.
public struct TorahSourcePath: Hashable, Sendable {
    /// Ordered ancestor nodes from root to the current position.
    public let segments: [TorahSourceNode]

    public init(segments: [TorahSourceNode] = []) {
        self.segments = segments
    }

    /// The terminal node in this path.
    public var current: TorahSourceNode? { segments.last }

    /// Breadcrumb labels for display.
    public var breadcrumbs: [String] { segments.map(\.labelHe) }
}

/// Full hierarchy tree with metadata.
public struct TorahSourceHierarchy: Sendable {
    /// Top-level categories (e.g. תנ״ך, משנה, תלמוד, etc.)
    public let roots: [TorahSourceNode]
    /// Provider that built this hierarchy.
    public let providerID: String
    /// When this hierarchy was last refreshed.
    public let fetchedAt: Date

    public init(roots: [TorahSourceNode], providerID: String, fetchedAt: Date = Date()) {
        self.roots = roots; self.providerID = providerID; self.fetchedAt = fetchedAt
    }
}

// MARK: - Hierarchy provider protocol

/// Protocol for building Torah source hierarchies from external providers.
/// Sefaria is the first implementation; Otzaria plugs in without changing this protocol.
public protocol TorahHierarchyProvider: Sendable {
    var providerID: String { get }
    /// Fetch/build the full hierarchy structure.
    /// Implementations should cache aggressively since the TOC rarely changes.
    func fetchHierarchy() async throws -> TorahSourceHierarchy
}

// MARK: - Path compression (UI projection)

public extension TorahSourceNode {
    /// Compress single-child chains in the UI: skip meaningless intermediate
    /// nodes that have only one available child and no direct leaves.
    /// Returns the compressed children for display, preserving the full
    /// canonical tree structure underneath.
    ///
    /// Example: if `תלמוד -> בבלי -> ראשונים -> רמב"ן` each have one child,
    /// the UI jumps directly to the first meaningful branch.
    var compressedChildren: [TorahSourceNode] {
        if children.count == 1 && !hasDirectLeaves {
            let child = children[0]
            if child.children.isEmpty && child.hasDirectLeaves {
                // Terminal node with leaves — show it
                return [child]
            }
            // Single-child passthrough — compress
            return child.compressedChildren
        }
        return children
    }

    /// The compressed display node: if this node is a single-child chain,
    /// returns the first meaningful descendant (node with multiple children
    /// or direct leaves). Used for auto-descent in the UI.
    var compressedTarget: TorahSourceNode {
        if children.count == 1 && !hasDirectLeaves {
            return children[0].compressedTarget
        }
        return self
    }

    /// Build the full path from root to a compressed target, collecting
    /// all intermediate nodes that were skipped.
    func compressedPath() -> TorahSourcePath {
        var segments: [TorahSourceNode] = [self]
        var current = self
        while current.children.count == 1 && !current.hasDirectLeaves {
            current = current.children[0]
            segments.append(current)
        }
        return TorahSourcePath(segments: segments)
    }
}
