import Foundation

/// Sefaria-specific hierarchy provider that builds a `TorahSourceHierarchy`
/// from the Sefaria Table of Contents API and Index v2 endpoints.
///
/// The TOC is large and rarely changing, so it is cached through the existing
/// `torah_provider_cache` table. Index v2 data is fetched lazily on demand.
///
/// Sefaria schema concepts (categories, `JaggedArrayNode`, section/address
/// information, content counts) are used only inside this adapter. The public
/// hierarchy model stays provider-neutral.
public struct SefariaHierarchyProvider: TorahHierarchyProvider {
    public let providerID = "sefaria"
    private let client: SefariaClient

    private let client: SefariaClient
    private let store: TorahStore?

    public init(client: SefariaClient = SefariaClient(), store: TorahStore? = nil) {
        self.client = client
        self.store = store
    }

    /// Fetch the Sefaria TOC and build a provider-neutral hierarchy conforming to TorahHierarchyProvider.
    public func fetchHierarchy() async throws -> TorahSourceHierarchy {
        try await fetchHierarchy(store: self.store)
    }

    /// Fetch the Sefaria TOC and build a provider-neutral hierarchy.
    /// Caches the raw TOC JSON through `torah_provider_cache` with a 7-day TTL when a store is available.
    public func fetchHierarchy(store: TorahStore?) async throws -> TorahSourceHierarchy {
        let cacheKey = "sefaria-toc-v1"
        let data: Data

        if let store,
           let cached = try await store.cached(providerID: providerID, key: cacheKey),
           let cachedData = cached.data(using: String.Encoding.utf8) {
            data = cachedData
        } else {
            let (fetchedData, response) = try await client.get(pathSegments: ["api", "index"])
            guard response.statusCode == 200 else {
                throw TorahError.network("Sefaria TOC returned HTTP \(response.statusCode).")
            }
            data = fetchedData
            if let store {
                let payload = String(decoding: fetchedData, as: UTF8.self)
                let ttl: TimeInterval = 7 * 24 * 60 * 60 // 7 days
                try await store.cache(providerID: providerID, key: cacheKey, payload: payload, expiresAt: Date().addingTimeInterval(ttl))
            }
        }

        guard let toc = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TorahError.malformedResponse
        }

        let roots = parseTOCNodes(toc, pathPrefix: "")
        return TorahSourceHierarchy(roots: roots, providerID: providerID)
    }

    // MARK: - TOC parsing

    /// Recursively parse Sefaria TOC entries into provider-neutral nodes.
    private func parseTOCNodes(_ entries: [[String: Any]], pathPrefix: String) -> [TorahSourceNode] {
        entries.compactMap { entry -> TorahSourceNode? in
            if let category = entry["category"] as? String {
                // Category node
                let heCategory = (entry["heCategory"] as? String) ?? category
                let nodeId = pathPrefix.isEmpty ? category : "\(pathPrefix)/\(category)"
                let contents = entry["contents"] as? [[String: Any]] ?? []
                let children = parseTOCNodes(contents, pathPrefix: nodeId)
                guard !children.isEmpty else { return nil }
                return TorahSourceNode(
                    id: nodeId,
                    labelHe: heCategory,
                    labelEn: category,
                    children: children
                )
            } else if let title = entry["title"] as? String {
                // Index (book/work) node
                let heTitle = (entry["heTitle"] as? String) ?? title
                let nodeId = pathPrefix.isEmpty ? title : "\(pathPrefix)/\(title)"
                return TorahSourceNode(
                    id: nodeId,
                    labelHe: heTitle,
                    labelEn: title,
                    canonicalKey: title
                )
            }
            return nil
        }
    }
}

// MARK: - Hierarchy filtering (only branches with user associations)

public extension TorahSourceHierarchy {
    /// Filter the hierarchy to only include branches that lead to at least one
    /// Pinkha page association. Annotates nodes with descendant leaf counts.
    ///
    /// - Parameter associatedKeys: Set of canonical keys that have Pinkha associations.
    /// - Returns: A new hierarchy containing only relevant branches.
    func filtered(byAssociatedKeys associatedKeys: Set<String>) -> TorahSourceHierarchy {
        let filteredRoots = roots.compactMap { $0.filtered(byAssociatedKeys: associatedKeys) }
        return TorahSourceHierarchy(roots: filteredRoots, providerID: providerID, fetchedAt: fetchedAt)
    }
}

private extension TorahSourceNode {
    /// Recursively filter: keep nodes whose canonical key is in the set,
    /// or whose descendants include associated keys. Annotates counts.
    func filtered(byAssociatedKeys keys: Set<String>) -> TorahSourceNode? {
        let directMatch = canonicalKey.map { keys.contains($0) } ?? false
        let filteredChildren = children.compactMap { $0.filtered(byAssociatedKeys: keys) }

        if !directMatch && filteredChildren.isEmpty { return nil }

        let childLeafCount = filteredChildren.reduce(0) { $0 + $1.descendantLeafCount }
        let totalCount = (directMatch ? 1 : 0) + childLeafCount

        return TorahSourceNode(
            id: id,
            labelHe: labelHe,
            labelEn: labelEn,
            canonicalKey: canonicalKey,
            children: filteredChildren,
            descendantLeafCount: totalCount,
            hasDirectLeaves: directMatch
        )
    }
}
