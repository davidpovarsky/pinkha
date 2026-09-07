import Foundation
import PinkhaFFI
import PinkhaCore
import PinkhaTorahCore

public extension LeafViewModel {

    /// Inserts a block content into the block tree as a sibling immediately after `afterId`,
    /// or at document root end if `afterId` is nil or not found.
    /// Preserves nesting hierarchy and updates flattened blocks accurately.
    @discardableResult
    func insertBlockContent(
        content: BlockContentFfi,
        spans: [InlineTextFfi] = [],
        afterId: String? = nil
    ) throws -> String {
        let parent: String?
        let sibling: Int
        let targetDepth: Int
        let insertionIndex: Int

        if let afterId, let idx = blocks.firstIndex(where: { $0.id == afterId }) {
            parent = parentId(of: idx)
            sibling = siblingIndex(of: idx) + 1
            targetDepth = blocks[idx].depth
            insertionIndex = idx + 1 + descendantRunLength(at: idx)
        } else {
            // Document end (root level)
            parent = nil
            let rootCount = blocks.filter { $0.depth == 0 }.count
            sibling = rootCount
            targetDepth = 0
            insertionIndex = blocks.count
        }

        let newId = UUID().uuidString
        let block = BlockFfi(
            id: newId,
            content: content,
            children: [],
            color: nil,
            backgroundColor: nil,
            textDirection: textDirection
        )
        let data = try JSONEncoder().encode(block)
        try api.insertBlockTree(
            leafId: leafId,
            blockJson: String(decoding: data, as: UTF8.self),
            parentId: parent,
            index: UInt32(sibling)
        )

        var newEditable = EditableBlock(id: newId, content: content, spans: spans, done: false)
        newEditable.depth = targetDepth
        newEditable.textDirection = textDirection

        let at = min(insertionIndex, blocks.count)
        blocks.insert(newEditable, at: at)
        blockSnapshots[newId] = snapshotOf(newEditable)
        autoFocusOffset = nil
        autoFocusId = newId

        return newId
    }

    /// Single reusable insertion pipeline for Torah source snapshots.
    /// Used by Segment Details "Insert into document", Context Menu "Insert", and Drag & Drop.
    /// Rolls back block creation if association persistence fails.
    func insertTorahSourceSnapshot(
        transfer: TorahSourceTransfer,
        afterId: String?,
        databasePath: String
    ) async throws {
        let workspace = try TorahWorkspace.application(databasePath: databasePath)

        let content = BlockContentFfi.quote(
            icon: "",
            text: [InlineTextFfi(content: transfer.text, styles: [])]
        )

        // 1. Create Quote block in editor tree
        let newBlockId = try insertBlockContent(
            content: content,
            spans: [InlineTextFfi(content: transfer.text, styles: [])],
            afterId: afterId
        )

        // 2. Persist Torah association
        do {
            let target = TorahTarget.block(leafID: leafId, blockID: newBlockId)
            let synthesizedDoc = TorahTextDocument(
                providerID: transfer.providerID,
                requestedRef: transfer.canonicalRef,
                canonicalRef: transfer.canonicalRef,
                hebrewRef: transfer.hebrewRef,
                sectionRef: transfer.sectionRef ?? transfer.canonicalRef,
                hebrewSectionRef: transfer.hebrewRef,
                segments: [
                    TorahTextSegment(
                        canonicalRef: transfer.canonicalRef,
                        hebrewRef: transfer.hebrewRef,
                        text: transfer.text,
                        ordinal: 1
                    )
                ],
                previousSectionRef: nil,
                nextSectionRef: nil,
                version: TorahTextVersionMetadata(
                    language: "he",
                    actualLanguage: "he",
                    languageFamilyName: "hebrew",
                    versionTitle: transfer.versionTitle ?? "",
                    versionTitleInHebrew: nil,
                    license: transfer.license,
                    direction: "rtl"
                ),
                rawProviderPayload: transfer.rawProviderPayload
            )
            let provenance = TorahSourceQuoteProvenance(
                retrievedAt: transfer.retrievedAt,
                canonicalRef: transfer.canonicalRef,
                referenceProviderPayload: transfer.rawProviderPayload,
                textDocument: synthesizedDoc
            )
            let payload = (try? String(decoding: JSONEncoder().encode(provenance), as: UTF8.self)) ?? transfer.rawProviderPayload

            let association = TorahAssociation(
                target: target,
                kind: .ref,
                role: .sourceQuote,
                providerID: transfer.providerID,
                externalID: transfer.canonicalRef,
                canonicalKey: transfer.canonicalRef,
                labelHe: transfer.hebrewRef ?? transfer.canonicalRef,
                labelEn: transfer.canonicalRef,
                rawInput: transfer.hebrewRef ?? transfer.canonicalRef,
                providerPayload: payload
            )
            try await workspace.add(association, to: target)

            // Register undo: removes association and deletes block
            undoMgr.registerUndo(withTarget: self) { vm in
                Task { @MainActor in
                    try? await workspace.remove(associationID: association.id)
                }
                vm.deleteBlock(id: newBlockId)
            }
        } catch {
            // Rollback block if association creation failed!
            deleteBlock(id: newBlockId)
            throw error
        }
    }
}
