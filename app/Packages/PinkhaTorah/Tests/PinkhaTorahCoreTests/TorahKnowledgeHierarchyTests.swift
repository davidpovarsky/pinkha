import Foundation
import Testing
@testable import PinkhaTorahCore

private func temporaryDatabase() throws -> (URL, String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (directory, directory.appendingPathComponent("pinkha.db").path)
}

@Suite("Torah Knowledge and Hierarchy Tests")
struct TorahKnowledgeHierarchyTests {

    // MARK: - Reverse Association Grouping and Counts

    @Test func reverseAssociationGroupingAndCounts() async throws {
        let (directory, path) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TorahStore(databasePath: path)

        // Leaf 1: Genesis 1:1 and Prayer topic
        let leaf1 = TorahTarget.leaf("leaf-1")
        try await store.add(TorahAssociation(
            target: leaf1, kind: .ref, providerID: "sefaria",
            externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית א׳:א׳"
        ))
        try await store.add(TorahAssociation(
            target: leaf1, kind: .topic, providerID: "sefaria",
            externalID: "prayer", canonicalKey: "prayer", labelHe: "תפילה"
        ))

        // Leaf 2: Genesis 1:1 (second doc referencing same source)
        let leaf2 = TorahTarget.leaf("leaf-2")
        try await store.add(TorahAssociation(
            target: leaf2, kind: .ref, providerID: "sefaria",
            externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית א׳:א׳"
        ))

        // Leaf 3: Exodus 20:2
        let leaf3 = TorahTarget.leaf("leaf-3")
        try await store.add(TorahAssociation(
            target: leaf3, kind: .ref, providerID: "sefaria",
            externalID: "Exodus 20:2", canonicalKey: "Exodus 20:2", labelHe: "שמות כ׳:ב׳"
        ))

        // Query grouped ref associations
        let refGroups = try await store.distinctAssociationGroups(kind: .ref)
        #expect(refGroups.count == 2)
        // Genesis 1:1 has 2 leaves, Exodus 20:2 has 1 leaf -> Genesis ordered first
        #expect(refGroups[0].canonicalKey == "Genesis 1:1")
        #expect(refGroups[0].leafCount == 2)
        #expect(refGroups[0].labelHe == "בראשית א׳:א׳")

        #expect(refGroups[1].canonicalKey == "Exodus 20:2")
        #expect(refGroups[1].leafCount == 1)

        // Query leaf IDs for Genesis 1:1
        let genesisLeaves = try await store.leafIDs(forCanonicalKey: "Genesis 1:1", kind: .ref)
        #expect(Set(genesisLeaves) == Set(["leaf-1", "leaf-2"]))

        // Query all pairs
        let pairs = try await store.allLeafAssociationPairs(kind: .ref)
        #expect(pairs.count == 3)

        // Query topic groups
        let topicGroups = try await store.distinctAssociationGroups(kind: .topic)
        #expect(topicGroups.count == 1)
        #expect(topicGroups[0].canonicalKey == "prayer")
        #expect(topicGroups[0].leafCount == 1)
    }

    // MARK: - Single-Child Path Compression (UI Projection)

    @Test func singleChildPathCompressionPreservesCanonicalTree() {
        // Build a hierarchy with a single-child chain:
        // Talmud -> Bavli -> Seder Moed -> Rosh Hashanah (has 2 children)
        let perek1 = TorahSourceNode(id: "rh-1", labelHe: "פרק א׳", canonicalKey: "Rosh Hashanah 2a", descendantLeafCount: 3, hasDirectLeaves: true)
        let perek2 = TorahSourceNode(id: "rh-2", labelHe: "פרק ב׳", canonicalKey: "Rosh Hashanah 22a", descendantLeafCount: 2, hasDirectLeaves: true)
        let tractate = TorahSourceNode(id: "rh", labelHe: "ראש השנה", children: [perek1, perek2], descendantLeafCount: 5)
        let seder = TorahSourceNode(id: "moed", labelHe: "סדר מועד", children: [tractate], descendantLeafCount: 5)
        let bavli = TorahSourceNode(id: "bavli", labelHe: "בבלי", children: [seder], descendantLeafCount: 5)
        let talmud = TorahSourceNode(id: "talmud", labelHe: "תלמוד", children: [bavli], descendantLeafCount: 5)

        // Full underlying tree structure is preserved
        #expect(talmud.children.count == 1)
        #expect(talmud.children[0].id == "bavli")
        #expect(talmud.children[0].children[0].id == "moed")

        // UI Projection / compression:
        // talmud.compressedChildren skips bavli and seder moed directly to tractate (which has multiple children)
        let compressed = talmud.compressedChildren
        #expect(compressed.count == 1)
        #expect(compressed[0].id == "rh")
        #expect(compressed[0].labelHe == "ראש השנה")
        #expect(compressed[0].children.count == 2)

        // Auto-descent target
        let target = talmud.compressedTarget
        #expect(target.id == "rh")

        // Full path collection for breadcrumbs
        let path = talmud.compressedPath()
        #expect(path.segments.map(\.id) == ["talmud", "bavli", "moed", "rh"])
        #expect(path.breadcrumbs == ["תלמוד", "בבלי", "סדר מועד", "ראש השנה"])
    }

    // MARK: - Sefaria Hierarchy Filtering

    @Test func sefariaHierarchyFilteredByAssociatedKeys() {
        let gen1 = TorahSourceNode(id: "gen", labelHe: "בראשית", canonicalKey: "Genesis", descendantLeafCount: 1, hasDirectLeaves: true)
        let torah = TorahSourceNode(id: "torah", labelHe: "תורה", children: [gen1])

        let ber1 = TorahSourceNode(id: "ber", labelHe: "ברכות", canonicalKey: "Berakhot", descendantLeafCount: 0, hasDirectLeaves: false)
        let mishnah = TorahSourceNode(id: "mishnah", labelHe: "משנה", children: [ber1])

        let fullHierarchy = TorahSourceHierarchy(roots: [torah, mishnah], providerID: "sefaria")

        // Filter by user associations that only include Genesis
        let filtered = fullHierarchy.filtered(byAssociatedKeys: ["Genesis"])

        #expect(filtered.roots.count == 1)
        #expect(filtered.roots[0].id == "torah")
        #expect(filtered.roots[0].children.count == 1)
        #expect(filtered.roots[0].children[0].id == "gen")
        #expect(filtered.roots[0].children[0].descendantLeafCount == 1)
    }

    // MARK: - Excerpt Provenance Encoding / Backward Compatibility

    @Test func excerptProvenanceRoundTripAndBackwardCompatibility() throws {
        let sampleDoc = TorahTextDocument(
            providerID: "sefaria",
            requestedRef: "Genesis 1:1",
            canonicalRef: "Genesis 1:1",
            hebrewRef: "בראשית א׳:א׳",
            sectionRef: "Genesis 1",
            hebrewSectionRef: "בראשית א׳",
            segments: [TorahTextSegment(canonicalRef: "Genesis 1:1", text: "בְּרֵאשִׁית בָּרָא אֱלֹהִים", ordinal: 1)],
            previousSectionRef: nil,
            nextSectionRef: nil,
            version: TorahTextVersionMetadata(
                language: "he", actualLanguage: "he", languageFamilyName: "hebrew",
                versionTitle: "Tanach", versionTitleInHebrew: "תנ״ך", license: "Public Domain", direction: "rtl"
            ),
            rawProviderPayload: "{}"
        )

        let excerpt = TorahSourceQuoteExcerpt(
            selectedText: "בְּרֵאשִׁית",
            segmentIndex: 0,
            characterOffset: 0,
            characterLength: 10
        )

        let provenanceWithExcerpt = TorahSourceQuoteProvenance(
            canonicalRef: "Genesis 1:1",
            referenceProviderPayload: "{}",
            textDocument: sampleDoc,
            excerpt: excerpt
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(provenanceWithExcerpt)
        let decoded = try decoder.decode(TorahSourceQuoteProvenance.self, from: data)

        #expect(decoded.canonicalRef == "Genesis 1:1")
        #expect(decoded.excerpt != nil)
        #expect(decoded.excerpt?.selectedText == "בְּרֵאשִׁית")
        #expect(decoded.excerpt?.characterLength == 10)

        // Backward compatibility: decode JSON without excerpt
        let legacyJSON = """
        {
            "retrievedAt": 0,
            "canonicalRef": "Genesis 1:1",
            "referenceProviderPayload": "{}",
            "textDocument": \(String(decoding: try encoder.encode(sampleDoc), as: UTF8.self))
        }
        """.data(using: .utf8)!

        let legacyDecoded = try decoder.decode(TorahSourceQuoteProvenance.self, from: legacyJSON)
        #expect(legacyDecoded.canonicalRef == "Genesis 1:1")
        #expect(legacyDecoded.excerpt == nil)
    }

    // MARK: - Broad Reference Resolution and Routing

    @Test func broadReferenceDetection() {
        // Tractate-level reference: nodeType = JaggedArrayNode, depth = 2, startIndexes = []
        // isEmbeddableSource should be false
        let broad = ResolvedReference(
            canonical: "Rosh Hashanah",
            labelHe: "ראש השנה",
            nodeType: "JaggedArrayNode",
            depth: 2,
            startIndexes: [],
            endIndexes: [],
            firstAvailableSectionRef: "Rosh Hashanah 2a"
        )
        #expect(broad.isEmbeddableSource == false)
        #expect(broad.firstAvailableSectionRef == "Rosh Hashanah 2a")

        // Specific section: startIndexes = [0, 0], depth = 2 -> embeddable!
        let specific = ResolvedReference(
            canonical: "Rosh Hashanah 2a:1",
            labelHe: "ראש השנה ב׳ א:א׳",
            nodeType: "JaggedArrayNode",
            depth: 2,
            startIndexes: [0, 0],
            endIndexes: [0, 0],
            firstAvailableSectionRef: nil
        )
        #expect(specific.isEmbeddableSource == true)

        // Single depth node (e.g. Proverbs 1)
        let singleDepth = ResolvedReference(
            canonical: "Proverbs 1",
            labelHe: "משלי א׳",
            nodeType: "JaggedArrayNode",
            depth: 1,
            startIndexes: [0],
            endIndexes: [0]
        )
        #expect(singleDepth.isEmbeddableSource == true)
    }

    // MARK: - TorahReferenceUtil Tests

    @Test func torahReferenceUtilExtraction() {
        #expect(TorahReferenceUtil.bookTitle(from: "Genesis 1:1") == "Genesis")
        #expect(TorahReferenceUtil.bookTitle(from: "Genesis 1") == "Genesis")
        #expect(TorahReferenceUtil.bookTitle(from: "Genesis") == "Genesis")
        #expect(TorahReferenceUtil.bookTitle(from: "Rosh Hashanah 16b") == "Rosh Hashanah")
        #expect(TorahReferenceUtil.bookTitle(from: "Rosh Hashanah 16b:1") == "Rosh Hashanah")
        #expect(TorahReferenceUtil.bookTitle(from: "I Kings 3:1") == "I Kings")
        #expect(TorahReferenceUtil.bookTitle(from: "Song of Songs 1:1") == "Song of Songs")

        #expect(TorahReferenceUtil.sectionRef(from: "Genesis 1:5") == "Genesis 1")
        #expect(TorahReferenceUtil.sectionRef(from: "Genesis 1") == "Genesis 1")
        #expect(TorahReferenceUtil.sectionRef(from: "Berakhot 2a:1") == "Berakhot 2a")
        #expect(TorahReferenceUtil.sectionRef(from: "Rosh Hashanah 16b") == "Rosh Hashanah 16b")

        #expect(TorahReferenceUtil.isSegmentRef("Genesis 1:5") == true)
        #expect(TorahReferenceUtil.isSegmentRef("Genesis 1") == false)
    }

    // MARK: - Book-Level Leaf Query Matches Associated Verses

    @Test func storeLeafIDsQueryMatchesSubReferences() async throws {
        let (directory, path) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TorahStore(databasePath: path)

        let leaf1 = TorahTarget.leaf("leaf-verse-1")
        try await store.add(TorahAssociation(
            target: leaf1, kind: .ref, providerID: "sefaria",
            externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית א׳:א׳"
        ))

        let leaf2 = TorahTarget.leaf("leaf-verse-2")
        try await store.add(TorahAssociation(
            target: leaf2, kind: .ref, providerID: "sefaria",
            externalID: "Genesis 1:5", canonicalKey: "Genesis 1:5", labelHe: "בראשית א׳:ה׳"
        ))

        let leaf3 = TorahTarget.leaf("leaf-talmud")
        try await store.add(TorahAssociation(
            target: leaf3, kind: .ref, providerID: "sefaria",
            externalID: "Rosh Hashanah 16b", canonicalKey: "Rosh Hashanah 16b", labelHe: "ראש השנה ט״ז ב׳"
        ))

        // Querying by book title "Genesis" finds both verse associations!
        let bookLeaves = try await store.leafIDs(forCanonicalKey: "Genesis", kind: .ref)
        #expect(Set(bookLeaves) == Set(["leaf-verse-1", "leaf-verse-2"]))

        // Querying by section "Genesis 1" finds both verse associations!
        let sectionLeaves = try await store.leafIDs(forCanonicalKey: "Genesis 1", kind: .ref)
        #expect(Set(sectionLeaves) == Set(["leaf-verse-1", "leaf-verse-2"]))

        // Querying exact verse "Genesis 1:1" finds only leaf1!
        let verseLeaves = try await store.leafIDs(forCanonicalKey: "Genesis 1:1", kind: .ref)
        #expect(verseLeaves == ["leaf-verse-1"])

        // Querying "Rosh Hashanah" finds leaf3!
        let talmudLeaves = try await store.leafIDs(forCanonicalKey: "Rosh Hashanah", kind: .ref)
        #expect(talmudLeaves == ["leaf-talmud"])
    }

    // MARK: - Hierarchy Filtering with Verse Associations

    @Test func hierarchyFilteredWithVerseAssociationsPreservesBooksAndCreatesChildren() {
        let genesisBook = TorahSourceNode(id: "gen", labelHe: "בראשית", canonicalKey: "Genesis")
        let exodusBook = TorahSourceNode(id: "exo", labelHe: "שמות", canonicalKey: "Exodus")
        let torahCategory = TorahSourceNode(id: "torah", labelHe: "תורה", children: [genesisBook, exodusBook])
        let hierarchy = TorahSourceHierarchy(roots: [torahCategory], providerID: "sefaria")

        let associations = [
            (canonicalKey: "Genesis 1:1", labelHe: "בראשית א׳:א׳", leafCount: 2),
            (canonicalKey: "Genesis 2:4", labelHe: "בראשית ב׳:ד׳", leafCount: 1)
        ]
        let associatedKeys = Set(associations.map(\.canonicalKey))

        let filtered = hierarchy.filtered(byAssociatedKeys: associatedKeys, associationGroups: associations)

        #expect(filtered.roots.count == 1)
        let root = filtered.roots[0]
        #expect(root.id == "torah")
        #expect(root.children.count == 1)

        let book = root.children[0]
        #expect(book.canonicalKey == "Genesis")
        #expect(book.descendantLeafCount == 3)
        #expect(book.children.count == 2)
        #expect(book.children[0].canonicalKey == "Genesis 1:1")
        #expect(book.children[0].descendantLeafCount == 2)
        #expect(book.children[1].canonicalKey == "Genesis 2:4")
        #expect(book.children[1].descendantLeafCount == 1)
    }

    // MARK: - Fetch Section Text via TorahWorkspace

    @Test func fetchSectionTextLoadsFullSection() async throws {
        let (directory, path) = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: directory) }

        let workspace = try TorahWorkspace.application(databasePath: path, arguments: ["--ui-test-torah-provider"])

        // Requesting section text for a verse "Genesis 1:5" fetches the entire chapter "Genesis 1"
        let doc = try await workspace.fetchSectionText(reference: "Genesis 1:5")
        #expect(doc.sectionRef == "Genesis 1")
        #expect(doc.segments.count >= 3)
        #expect(doc.nextSectionRef == "Genesis 2")
    }
}
