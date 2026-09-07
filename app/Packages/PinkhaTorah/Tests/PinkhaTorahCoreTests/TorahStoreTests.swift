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
}
