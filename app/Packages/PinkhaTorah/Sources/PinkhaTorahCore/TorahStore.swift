import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public actor TorahStore {
    private var db: OpaquePointer?
    private let encoder = ISO8601DateFormatter()

    public init(databasePath: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            throw TorahError.storage("Unable to open Torah storage.")
        }
        db = handle
        sqlite3_busy_timeout(handle, 3_000)
        do { try Self.migrate(handle) }
        catch { sqlite3_close(handle); db = nil; throw error }
    }

    isolated deinit { if let db { sqlite3_close(db) } }

    private static func migrate(_ db: OpaquePointer) throws {
        let sql = """
        BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS torah_schema_migrations (
          version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS torah_associations (
          id TEXT PRIMARY KEY, target_kind TEXT NOT NULL, leaf_id TEXT NOT NULL,
          target_id TEXT NOT NULL, kind TEXT NOT NULL, provider_id TEXT NOT NULL,
          external_id TEXT NOT NULL, canonical_key TEXT NOT NULL, label_he TEXT NOT NULL,
          label_en TEXT, raw_input TEXT, payload_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS torah_assoc_target ON torah_associations(target_kind, target_id);
        CREATE INDEX IF NOT EXISTS torah_assoc_leaf ON torah_associations(leaf_id);
        CREATE INDEX IF NOT EXISTS torah_assoc_canonical ON torah_associations(kind, provider_id, canonical_key);
        CREATE UNIQUE INDEX IF NOT EXISTS torah_assoc_no_exact_duplicates
          ON torah_associations(target_kind, target_id, kind, provider_id, canonical_key);
        CREATE TABLE IF NOT EXISTS torah_provider_cache (
          provider_id TEXT NOT NULL, cache_key TEXT NOT NULL, payload_json TEXT NOT NULL,
          expires_at TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(provider_id, cache_key)
        );
        CREATE TABLE IF NOT EXISTS torah_topics_cache (
          provider_id TEXT NOT NULL, slug TEXT NOT NULL, primary_he TEXT, primary_en TEXT,
          search_text TEXT NOT NULL, payload_json TEXT NOT NULL, updated_at TEXT NOT NULL,
          PRIMARY KEY(provider_id, slug)
        );
        INSERT OR IGNORE INTO torah_schema_migrations(version, applied_at)
          VALUES(1, strftime('%Y-%m-%dT%H:%M:%fZ','now'));
        COMMIT;
        """
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "Torah migration failed."
            sqlite3_free(error); sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw TorahError.storage(message)
        }
    }

    public func associations(for target: TorahTarget) throws -> [TorahAssociation] {
        let sql = """
        SELECT id, kind, provider_id, external_id, canonical_key, label_he, label_en,
               raw_input, payload_json, created_at, updated_at
        FROM torah_associations WHERE target_kind = ? AND target_id = ?
        ORDER BY created_at, id
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(target.targetKind, at: 1, to: statement); bind(target.targetID, at: 2, to: statement)
        var values: [TorahAssociation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kind = TorahAssociationKind(rawValue: text(statement, 1)) else { continue }
            values.append(TorahAssociation(
                id: text(statement, 0), target: target, kind: kind,
                providerID: text(statement, 2), externalID: text(statement, 3),
                canonicalKey: text(statement, 4), labelHe: text(statement, 5),
                labelEn: optionalText(statement, 6), rawInput: optionalText(statement, 7),
                providerPayload: text(statement, 8),
                createdAt: encoder.date(from: text(statement, 9)) ?? .distantPast,
                updatedAt: encoder.date(from: text(statement, 10)) ?? .distantPast
            ))
        }
        return values
    }

    public func add(_ value: TorahAssociation) throws {
        let sql = """
        INSERT OR IGNORE INTO torah_associations
        (id,target_kind,leaf_id,target_id,kind,provider_id,external_id,canonical_key,
         label_he,label_en,raw_input,payload_json,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        let values: [String?] = [value.id, value.target.targetKind, value.target.leafID,
            value.target.targetID, value.kind.rawValue, value.providerID, value.externalID,
            value.canonicalKey, value.labelHe, value.labelEn, value.rawInput,
            value.providerPayload, encoder.string(from: value.createdAt), encoder.string(from: value.updatedAt)]
        for (index, value) in values.enumerated() { bind(value, at: Int32(index + 1), to: statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    public func remove(id: String) throws {
        let statement = try prepare("DELETE FROM torah_associations WHERE id = ?")
        defer { sqlite3_finalize(statement) }; bind(id, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    public func cached(providerID: String, key: String, now: Date = Date()) throws -> String? {
        let statement = try prepare("SELECT payload_json, expires_at FROM torah_provider_cache WHERE provider_id=? AND cache_key=?")
        defer { sqlite3_finalize(statement) }
        bind(providerID, at: 1, to: statement); bind(key, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if let expiration = optionalText(statement, 1), let date = encoder.date(from: expiration), date <= now { return nil }
        return text(statement, 0)
    }

    public func cache(providerID: String, key: String, payload: String, expiresAt: Date?) throws {
        let statement = try prepare("""
        INSERT INTO torah_provider_cache(provider_id,cache_key,payload_json,expires_at,updated_at)
        VALUES(?,?,?,?,?) ON CONFLICT(provider_id,cache_key) DO UPDATE SET
        payload_json=excluded.payload_json, expires_at=excluded.expires_at, updated_at=excluded.updated_at
        """)
        defer { sqlite3_finalize(statement) }
        [providerID, key, payload, expiresAt.map { encoder.string(from: $0) }, encoder.string(from: Date())]
            .enumerated().forEach { bind($0.element, at: Int32($0.offset + 1), to: statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    public func replaceTopics(providerID: String, topics: [TopicCandidate], payloads: [String: String]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let delete = try prepare("DELETE FROM torah_topics_cache WHERE provider_id=?")
            bind(providerID, at: 1, to: delete)
            guard sqlite3_step(delete) == SQLITE_DONE else { sqlite3_finalize(delete); throw lastError() }
            sqlite3_finalize(delete)
            let insert = try prepare("INSERT INTO torah_topics_cache(provider_id,slug,primary_he,primary_en,search_text,payload_json,updated_at) VALUES(?,?,?,?,?,?,?)")
            defer { sqlite3_finalize(insert) }
            for topic in topics {
                sqlite3_reset(insert); sqlite3_clear_bindings(insert)
                let search = "\(topic.labelHe) \(topic.labelEn ?? "")".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                let values: [String?] = [providerID, topic.id, topic.labelHe, topic.labelEn, search, payloads[topic.id] ?? "{}", encoder.string(from: Date())]
                for (index, value) in values.enumerated() { bind(value, at: Int32(index + 1), to: insert) }
                guard sqlite3_step(insert) == SQLITE_DONE else { throw lastError() }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    public func searchTopics(providerID: String, query: String, limit: Int) throws -> [TopicCandidate] {
        let statement = try prepare("SELECT slug,primary_he,primary_en FROM torah_topics_cache WHERE provider_id=? AND search_text LIKE ? ORDER BY primary_he LIMIT ?")
        defer { sqlite3_finalize(statement) }
        bind(providerID, at: 1, to: statement)
        bind("%\(query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))%", at: 2, to: statement)
        sqlite3_bind_int(statement, 3, Int32(limit))
        var result: [TopicCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(TopicCandidate(id: text(statement, 0), labelHe: text(statement, 1), labelEn: optionalText(statement, 2)))
        }
        return result
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw TorahError.storage("Torah storage is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw lastError() }
        return statement
    }
    private func execute(_ sql: String) throws {
        guard let db, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }
    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer?) {
        if let value { sqlite3_bind_text(statement, index, value, -1, sqliteTransient) }
        else { sqlite3_bind_null(statement, index) }
    }
    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
    private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }
    private func lastError() -> TorahError {
        guard let db else { return .storage("Torah storage is closed.") }
        return .storage(String(cString: sqlite3_errmsg(db)))
    }
}
