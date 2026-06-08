import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum HistoryStoreError: LocalizedError {
    case openDatabaseFailed(String)
    case executeFailed(String)
    case statementPrepareFailed(String)

    var errorDescription: String? {
        switch self {
        case .openDatabaseFailed(let message):
            return "无法打开数据库: \(message)"
        case .executeFailed(let message):
            return "数据库执行失败: \(message)"
        case .statementPrepareFailed(let message):
            return "数据库语句准备失败: \(message)"
        }
    }
}

final class HistoryStore {
    private let iso8601Formatter: ISO8601DateFormatter
    private let queue = DispatchQueue(label: "EnglishCoach.HistoryStore")
    private var db: OpaquePointer?

    init(databaseURL: URL? = nil) throws {
        let resolvedURL = try databaseURL ?? Self.defaultDatabaseURL()
        iso8601Formatter = ISO8601DateFormatter()
        try openDatabase(at: resolvedURL)
        try createTablesIfNeeded()
    }

    deinit {
        queue.sync {
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
        }
    }

    func insertLookup(
        rawText: String,
        sourceApp: String?,
        context: String?,
        result: TranslationResult
    ) throws {
        try queue.sync {
            let sql = """
            INSERT INTO lookup_history (
                raw_text,
                normalized_text,
                source_app,
                translation,
                phonetic,
                explanations_json,
                context,
                provider,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw HistoryStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }

            let explanationsJSON: String
            do {
                let data = try JSONEncoder().encode(result.explanations)
                explanationsJSON = String(data: data, encoding: .utf8) ?? "[]"
            } catch {
                NSLog("[HistoryStore] failed to encode explanations: %@", error.localizedDescription)
                explanationsJSON = "[]"
            }

            bind(text: rawText, to: 1, statement: statement)
            bind(text: rawText.normalizedForLookup, to: 2, statement: statement)
            bind(text: sourceApp, to: 3, statement: statement)
            bind(text: result.translatedText, to: 4, statement: statement)
            bind(text: result.phonetic, to: 5, statement: statement)
            bind(text: explanationsJSON, to: 6, statement: statement)
            bind(text: context, to: 7, statement: statement)
            bind(text: result.provider, to: 8, statement: statement)
            bind(text: iso8601Formatter.string(from: Date()), to: 9, statement: statement)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.executeFailed(lastErrorMessage())
            }
        }
    }

    func fetchRecent(limit: Int = 200) throws -> [LookupHistoryItem] {
        try queue.sync {
            let sql = """
            SELECT
                id,
                raw_text,
                normalized_text,
                source_app,
                translation,
                phonetic,
                explanations_json,
                context,
                provider,
                created_at
            FROM lookup_history
            ORDER BY datetime(created_at) DESC
            LIMIT ?;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw HistoryStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(limit))

            var items: [LookupHistoryItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let rawText = stringColumn(statement, index: 1)
                let normalizedText = stringColumn(statement, index: 2)
                let sourceApp = optionalStringColumn(statement, index: 3)
                let translation = stringColumn(statement, index: 4)
                let phonetic = optionalStringColumn(statement, index: 5)
                let explanationsJSON = stringColumn(statement, index: 6)
                let context = optionalStringColumn(statement, index: 7)
                let provider = optionalStringColumn(statement, index: 8)
                let createdAtRaw = stringColumn(statement, index: 9)
                let date = iso8601Formatter.date(from: createdAtRaw) ?? Date()

                let explanations: [String]
                if let data = explanationsJSON.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String].self, from: data) {
                    explanations = decoded
                } else {
                    explanations = []
                }

                let item = LookupHistoryItem(
                    id: id,
                    rawText: rawText,
                    normalizedText: normalizedText,
                    sourceApp: sourceApp,
                    translation: translation,
                    phonetic: phonetic,
                    explanations: explanations,
                    context: context,
                    provider: provider,
                    createdAt: date
                )
                items.append(item)
            }

            return items
        }
    }

    func deleteHistory(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }

        try queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "DELETE FROM lookup_history WHERE id IN (\(placeholders));"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw HistoryStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }

            for (index, id) in ids.enumerated() {
                sqlite3_bind_int64(statement, Int32(index + 1), id)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.executeFailed(lastErrorMessage())
            }
        }
    }

    private static func defaultDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent("EnglishCoach", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("english_coach.sqlite3", isDirectory: false)
    }

    private func openDatabase(at url: URL) throws {
        try queue.sync {
            let status = sqlite3_open(url.path, &db)
            guard status == SQLITE_OK else {
                throw HistoryStoreError.openDatabaseFailed(lastErrorMessage())
            }
        }
    }

    private func createTablesIfNeeded() throws {
        try queue.sync {
            let sql = """
            CREATE TABLE IF NOT EXISTS lookup_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                raw_text TEXT NOT NULL,
                normalized_text TEXT NOT NULL,
                source_app TEXT,
                translation TEXT NOT NULL,
                phonetic TEXT,
                explanations_json TEXT NOT NULL,
                context TEXT,
                provider TEXT,
                created_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_lookup_history_created_at ON lookup_history(created_at);
            CREATE INDEX IF NOT EXISTS idx_lookup_history_normalized_text ON lookup_history(normalized_text);
            """

            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw HistoryStoreError.executeFailed(lastErrorMessage())
            }

            // Migrate databases created before the `context` column existed.
            // ADD COLUMN fails when the column is already present; that's
            // expected on up-to-date databases, so the error is ignored.
            if !columnExists(table: "lookup_history", column: "context") {
                sqlite3_exec(db, "ALTER TABLE lookup_history ADD COLUMN context TEXT;", nil, nil, nil)
            }
            if !columnExists(table: "lookup_history", column: "provider") {
                sqlite3_exec(db, "ALTER TABLE lookup_history ADD COLUMN provider TEXT;", nil, nil, nil)
            }
        }
    }

    /// Checks `PRAGMA table_info` for a column. Must be called on `queue`.
    private func columnExists(table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            // Column 1 of table_info is the column name.
            if let cName = sqlite3_column_text(statement, 1),
               String(cString: cName) == column {
                return true
            }
        }
        return false
    }

    private func bind(text: String?, to index: Int32, statement: OpaquePointer?) {
        guard let statement else { return }
        if let text {
            sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private func optionalStringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return stringColumn(statement, index: index)
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "Unknown database error" }
        return String(cString: sqlite3_errmsg(db))
    }
}
