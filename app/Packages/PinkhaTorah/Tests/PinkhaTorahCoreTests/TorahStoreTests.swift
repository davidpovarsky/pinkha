import CSQLite
import Foundation
import Testing
@testable import PinkhaTorahCore

private func temporaryDatabase() throws -> (URL, String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (directory, directory.appendingPathComponent("pinkha.db").path)
}

private func userVersion(_ path: String) throws -> Int32 {
    var db: OpaquePointer?; guard sqlite3_open(path, &db) == SQLITE_OK else { throw TorahError.storage("open") }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?; sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw TorahError.storage("pragma") }
    return sqlite3_column_int(statement, 0)
}

private struct SourceInsertionProvider: ReferenceProvider, TextProvider {
    let providerID = "insertion-test"
    var failText = false
    func suggestReferences(query: String, limit: Int) async throws -> [ReferenceCandidate] { [.init(id: "candidate-key", label: "כותרת")] }
    func resolveReference(_ input: String) async throws -> ResolvedReference {
        guard input == "candidate-key" else { throw TorahError.invalidReference }
        return .init(canonical: "Genesis 1:1", labelHe: "בראשית א׳:א׳", nodeType: "JaggedArrayNode", depth: 2, startIndexes: [0, 0])
    }
    func fetchText(reference: String, request: TorahTextRequest) async throws -> TorahTextDocument {
        if failText { throw TorahError.noText }
        return .init(providerID: providerID, requestedRef: reference, canonicalRef: reference, hebrewRef: "בראשית א׳:א׳", sectionRef: "Genesis 1", hebrewSectionRef: "בראשית א׳", segments: [.init(canonicalRef: reference, text: "בראשית", ordinal: 1)], previousSectionRef: nil, nextSectionRef: nil, version: .init(language: "he", actualLanguage: "he", languageFamilyName: "hebrew", versionTitle: "Test", versionTitleInHebrew: nil, license: nil, direction: "rtl"), rawProviderPayload: "{}")
    }
}

@Suite("Torah store")
struct TorahStoreTests {
    @Test func migrationIsIdempotentAndPreservesPinkhaVersion() async throws {
        let (directory, path) = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?; sqlite3_open(path, &db)
        sqlite3_exec(db, "PRAGMA user_version=73; CREATE TABLE pinkha_dummy(value TEXT);", nil, nil, nil)
        sqlite3_close(db)
        _ = try TorahStore(databasePath: path); _ = try TorahStore(databasePath: path)
        #expect(try userVersion(path) == 73)
    }

    @Test func crudMultipleKindsDuplicatePreventionAndTargetIsolation() async throws {
        let (directory, path) = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TorahStore(databasePath: path)
        let leaf = TorahTarget.leaf("leaf-1")
        let block = TorahTarget.block(leafID: "leaf-1", blockID: "block-1")
        let reference = TorahAssociation(target: leaf, kind: .ref, providerID: "sefaria", externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית א׳:א׳", providerPayload: #"{"ref":1}"#)
        try await store.add(reference); try await store.add(reference)
        try await store.add(TorahAssociation(target: leaf, kind: .topic, providerID: "sefaria", externalID: "prayer", canonicalKey: "prayer", labelHe: "תפילה"))
        try await store.add(TorahAssociation(target: leaf, kind: .word, providerID: "sefaria", externalID: "BDB|שער|1", canonicalKey: "BDB|שער|1", labelHe: "בשעריך"))
        try await store.add(TorahAssociation(target: block, kind: .ref, providerID: "sefaria", externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית א׳:א׳"))
        let leafValues = try await store.associations(for: leaf)
        #expect(leafValues.count == 3)
        #expect(leafValues.first(where: { $0.id == reference.id })?.providerPayload == #"{"ref":1}"#)
        #expect(try await store.associations(for: block).count == 1)
        try await store.remove(id: reference.id)
        #expect(try await store.associations(for: leaf).count == 2)
    }

    @Test func topicCacheSupportsSearchAndExpiration() async throws {
        let (directory, path) = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TorahStore(databasePath: path)
        let topic = TopicCandidate(id: "prayer", labelHe: "תפילה", labelEn: "Prayer")
        try await store.replaceTopics(providerID: "fake", topics: [topic], payloads: [topic.id: "{}"])
        #expect(try await store.searchTopics(providerID: "fake", query: "תפיל", limit: 10).map(\.id) == ["prayer"])
        try await store.cache(providerID: "fake", key: "fresh", payload: "yes", expiresAt: Date().addingTimeInterval(60))
        try await store.cache(providerID: "fake", key: "old", payload: "no", expiresAt: Date().addingTimeInterval(-1))
        #expect(try await store.cached(providerID: "fake", key: "fresh") == "yes")
        #expect(try await store.cached(providerID: "fake", key: "old") == nil)
    }

    @Test func associationRolesDefaultAndSourceQuoteRoundTrip() async throws {
        let (directory, path) = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TorahStore(databasePath: path)
        let target = TorahTarget.block(leafID: "leaf", blockID: "block")
        let context = TorahAssociation(target: target, kind: .ref, providerID: "sefaria", externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית")
        let source = TorahAssociation(target: target, kind: .ref, role: .sourceQuote, providerID: "sefaria", externalID: "Genesis 1:1", canonicalKey: "Genesis 1:1", labelHe: "בראשית", providerPayload: #"{"versionTitle":"Test"}"#)
        try await store.add(context); try await store.add(source)
        let values = try await store.associations(for: target)
        #expect(Set(values.map(\.role)) == [.context, .sourceQuote])
        #expect(values.first(where: { $0.role == .sourceQuote })?.providerPayload.contains("versionTitle") == true)
        #expect(try userVersion(path) == 0)
    }

    @Test func legacyAssociationRowsMigrateToContextWithoutChangingPinkhaVersion() async throws {
        let (directory, path) = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?; sqlite3_open(path, &db)
        let sql = """
        PRAGMA user_version=91;
        CREATE TABLE torah_associations (
          id TEXT PRIMARY KEY, target_kind TEXT NOT NULL, leaf_id TEXT NOT NULL, target_id TEXT NOT NULL,
          kind TEXT NOT NULL, provider_id TEXT NOT NULL, external_id TEXT NOT NULL, canonical_key TEXT NOT NULL,
          label_he TEXT NOT NULL, label_en TEXT, raw_input TEXT, payload_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        INSERT INTO torah_associations VALUES('old','leaf','leaf','leaf','ref','sefaria','Genesis 1:1','Genesis 1:1','בראשית',NULL,NULL,'{}','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z');
        """
        sqlite3_exec(db, sql, nil, nil, nil); sqlite3_close(db)
        let store = try TorahStore(databasePath: path)
        #expect(try await store.associations(for: .leaf("leaf")).first?.role == .context)
        #expect(try userVersion(path) == 91)
    }

    @MainActor @Test func sourceInsertionValidatesAndFetchesBeforePersistingSameBlockTarget() async throws {
        let (directory, path) = try temporaryDatabase(); defer { try? FileManager.default.removeItem(at: directory) }
        let provider = SourceInsertionProvider()
        let workspace = TorahWorkspace(store: try TorahStore(databasePath: path), registry: .init(referenceProviders: [provider], topicProviders: [], lexicalProviders: [], textProviders: [provider], defaultProviderID: provider.providerID))
        let candidate = try await workspace.suggestReferences("כותרת")[0]
        let resolved = try await workspace.resolveReference(candidate.id)
        let document = try await workspace.fetchText(reference: resolved.canonical)
        let target = TorahTarget.block(leafID: "leaf-id", blockID: "same-block-id")
        try await workspace.addSourceQuote(resolved, document: document, rawInput: "כותרת", to: target)
        let saved = try await workspace.associations(for: target).first
        #expect(saved?.target.targetID == "same-block-id")
        #expect(saved?.role == .sourceQuote)

        let failedProvider = SourceInsertionProvider(failText: true)
        let failedWorkspace = TorahWorkspace(store: try TorahStore(databasePath: path), registry: .init(referenceProviders: [failedProvider], topicProviders: [], lexicalProviders: [], textProviders: [failedProvider], defaultProviderID: failedProvider.providerID))
        await #expect(throws: TorahError.noText) { try await failedWorkspace.fetchText(reference: resolved.canonical) }
        #expect(try await failedWorkspace.associations(for: .block(leafID: "leaf-id", blockID: "untouched-block")).isEmpty)
    }
}
