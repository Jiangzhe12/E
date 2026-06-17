import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum TodoStoreError: LocalizedError {
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

/// SQLite-backed store for the ported todo list. Shares the same database file
/// as `HistoryStore`; each store owns its own connection, serialized on a
/// private queue, mirroring the existing store conventions.
final class TodoStore {
    private let iso8601Formatter: ISO8601DateFormatter
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let queue = DispatchQueue(label: "Nova.TodoStore")
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

    // MARK: - Todo CRUD

    func fetchAll() throws -> [TodoItem] {
        try queue.sync {
            let sql = """
            SELECT
                id, title, category, priority, status, date,
                created_at, updated_at, completed_at, sort_order, archived,
                due_date, note, bug_cause, fix_plan, converted_to_optimization_id,
                tags_json, subtasks_json, attachments_json, changelog_json
            FROM todo_items
            ORDER BY date DESC, sort_order ASC;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }

            var items: [TodoItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let createdAt = iso8601Formatter.date(from: stringColumn(statement, index: 6)) ?? Date()
                let updatedAt = iso8601Formatter.date(from: stringColumn(statement, index: 7)) ?? createdAt
                let item = TodoItem(
                    id: stringColumn(statement, index: 0),
                    title: stringColumn(statement, index: 1),
                    category: TodoCategory(rawValue: stringColumn(statement, index: 2)) ?? .feature,
                    priority: TodoPriority(rawValue: stringColumn(statement, index: 3)) ?? .medium,
                    status: TodoStatus(rawValue: stringColumn(statement, index: 4)) ?? .pending,
                    date: stringColumn(statement, index: 5),
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    completedAt: optionalStringColumn(statement, index: 8).flatMap { iso8601Formatter.date(from: $0) },
                    order: Int(sqlite3_column_int64(statement, 9)),
                    archived: sqlite3_column_int(statement, 10) != 0,
                    dueDate: optionalStringColumn(statement, index: 11),
                    note: optionalStringColumn(statement, index: 12),
                    tags: decodeJSON([String].self, optionalStringColumn(statement, index: 16)),
                    subtasks: decodeJSON([Subtask].self, optionalStringColumn(statement, index: 17)),
                    attachments: decodeJSON([String].self, optionalStringColumn(statement, index: 18)),
                    changelog: decodeJSON([ChangeLogEntry].self, optionalStringColumn(statement, index: 19)),
                    bugCause: optionalStringColumn(statement, index: 13),
                    fixPlan: optionalStringColumn(statement, index: 14),
                    convertedToOptimizationId: optionalStringColumn(statement, index: 15)
                )
                items.append(item)
            }
            return items
        }
    }

    func upsert(_ todo: TodoItem) throws {
        try queue.sync {
            try upsertOnQueue(todo)
        }
    }

    func upsertMany(_ todos: [TodoItem]) throws {
        guard !todos.isEmpty else { return }
        try queue.sync {
            guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
                throw TodoStoreError.executeFailed(lastErrorMessage())
            }
            do {
                for todo in todos {
                    try upsertOnQueue(todo)
                }
            } catch {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                throw TodoStoreError.executeFailed(lastErrorMessage())
            }
        }
    }

    func delete(id: String) throws {
        try deleteMany(ids: [id])
    }

    func deleteMany(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "DELETE FROM todo_items WHERE id IN (\(placeholders));"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }

            for (index, id) in ids.enumerated() {
                bind(text: id, to: Int32(index + 1), statement: statement)
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TodoStoreError.executeFailed(lastErrorMessage())
            }
        }
    }

    /// Completion timestamps of every todo that was ever finished — feeds the
    /// activity heatmap.
    func completionDates() throws -> [Date] {
        try queue.sync {
            let sql = "SELECT completed_at FROM todo_items WHERE completed_at IS NOT NULL;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }

            var dates: [Date] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let raw = optionalStringColumn(statement, index: 0),
                   let date = iso8601Formatter.date(from: raw) {
                    dates.append(date)
                }
            }
            return dates
        }
    }

    // MARK: - Key/value singletons

    func loadString(_ key: String) throws -> String? {
        try queue.sync {
            let sql = "SELECT value FROM todo_kv WHERE key = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }
            bind(text: key, to: 1, statement: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                return optionalStringColumn(statement, index: 0)
            }
            return nil
        }
    }

    func saveString(_ key: String, _ value: String?) throws {
        try queue.sync {
            guard let value else {
                let sql = "DELETE FROM todo_kv WHERE key = ?;"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
                }
                defer { sqlite3_finalize(statement) }
                bind(text: key, to: 1, statement: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw TodoStoreError.executeFailed(lastErrorMessage())
                }
                return
            }

            let sql = """
            INSERT INTO todo_kv (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(statement) }
            bind(text: key, to: 1, statement: statement)
            bind(text: value, to: 2, statement: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TodoStoreError.executeFailed(lastErrorMessage())
            }
        }
    }

    func loadJSON<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        guard let raw = try loadString(key) else { return nil }
        return decodeJSON(type, raw)
    }

    func saveJSON<T: Encodable>(_ key: String, _ value: T?) throws {
        try saveString(key, encodeJSON(value))
    }

    // MARK: - Convenience singleton wrappers

    func loadLastOpenDate() throws -> String? { try loadString("lastOpenDate") }
    func saveLastOpenDate(_ value: String) throws { try saveString("lastOpenDate", value) }

    func loadMemo() throws -> (text: String, updatedAt: Date?) {
        let text = (try loadString("memo")) ?? ""
        let updatedAt = (try loadString("memoUpdatedAt")).flatMap { iso8601Formatter.date(from: $0) }
        return (text, updatedAt)
    }

    func saveMemo(_ text: String, updatedAt: Date) throws {
        try saveString("memo", text)
        try saveString("memoUpdatedAt", iso8601Formatter.string(from: updatedAt))
    }

    func loadCustomTags() throws -> [String] { (try loadJSON("customTags", as: [String].self)) ?? [] }
    func saveCustomTags(_ tags: [String]) throws { try saveJSON("customTags", tags) }

    func loadTemplates() throws -> [TodoTemplate] { (try loadJSON("templates", as: [TodoTemplate].self)) ?? [] }
    func saveTemplates(_ templates: [TodoTemplate]) throws { try saveJSON("templates", templates) }

    func loadSavedReports() throws -> [String: String] { (try loadJSON("savedReports", as: [String: String].self)) ?? [:] }
    func saveSavedReports(_ reports: [String: String]) throws { try saveJSON("savedReports", reports) }

    // MARK: - Carry-over

    /// Applies daily carry-over when the day rolls over, persists the changed
    /// rows, and returns the resulting full list. No-op if already run today.
    func runCarryOver(today: String) throws -> [TodoItem] {
        let all = try fetchAll()
        if (try loadLastOpenDate()) == today {
            return all
        }
        let migrated = TodoCarryOver.apply(all, today: today)
        let changed = zip(all, migrated).compactMap { $0 != $1 ? $1 : nil }
        try upsertMany(changed)
        try saveLastOpenDate(today)
        return migrated
    }

    // MARK: - Legacy import

    /// One-time migration of the standalone TodoList-zhe app's data. Idempotent:
    /// guarded by a `migrationVersion` flag so re-launches never duplicate rows.
    /// Returns how many todos were imported (0 if skipped / no file).
    @discardableResult
    func importLegacyDataIfNeeded(from url: URL? = nil, today: String) throws -> Int {
        if (try loadString("migrationVersion")) == "1" { return 0 }

        let resolvedURL = url ?? Self.defaultLegacyDataURL()
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return 0
        }

        let data = try Data(contentsOf: resolvedURL)
        let result = try LegacyTodoDecoder.decode(data, today: today)

        try upsertMany(result.todos)
        if let memo = result.memo, !memo.isEmpty {
            try saveString("memo", memo)
            try saveString("memoUpdatedAt", iso8601Formatter.string(from: result.memoUpdatedAt ?? Date()))
        }
        if let last = result.lastOpenDate { try saveString("lastOpenDate", last) }
        if !result.savedReports.isEmpty { try saveSavedReports(result.savedReports) }
        if !result.customTags.isEmpty { try saveCustomTags(result.customTags) }
        if !result.templates.isEmpty { try saveTemplates(result.templates) }

        try saveString("migrationVersion", "1")
        return result.todos.count
    }

    // MARK: - Schema

    private static func defaultDatabaseURL() throws -> URL {
        try AppSupport.databaseURL()
    }

    private static func defaultLegacyDataURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/todo-desktop/todo-data.json", isDirectory: false)
    }

    private func openDatabase(at url: URL) throws {
        try queue.sync {
            let status = sqlite3_open(url.path, &db)
            guard status == SQLITE_OK else {
                throw TodoStoreError.openDatabaseFailed(lastErrorMessage())
            }
        }
    }

    private func createTablesIfNeeded() throws {
        try queue.sync {
            let sql = """
            CREATE TABLE IF NOT EXISTS todo_items (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                category TEXT NOT NULL,
                priority TEXT NOT NULL,
                status TEXT NOT NULL,
                date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                completed_at TEXT,
                sort_order INTEGER NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0,
                due_date TEXT,
                note TEXT,
                bug_cause TEXT,
                fix_plan TEXT,
                converted_to_optimization_id TEXT,
                tags_json TEXT,
                subtasks_json TEXT,
                attachments_json TEXT,
                changelog_json TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_todo_items_date ON todo_items(date);
            CREATE INDEX IF NOT EXISTS idx_todo_items_status ON todo_items(status);
            CREATE INDEX IF NOT EXISTS idx_todo_items_archived ON todo_items(archived);

            CREATE TABLE IF NOT EXISTS todo_kv (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """

            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw TodoStoreError.executeFailed(lastErrorMessage())
            }
        }
    }

    // MARK: - Helpers (must be called on `queue`)

    private func upsertOnQueue(_ todo: TodoItem) throws {
        let sql = """
        INSERT INTO todo_items (
            id, title, category, priority, status, date,
            created_at, updated_at, completed_at, sort_order, archived,
            due_date, note, bug_cause, fix_plan, converted_to_optimization_id,
            tags_json, subtasks_json, attachments_json, changelog_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            category = excluded.category,
            priority = excluded.priority,
            status = excluded.status,
            date = excluded.date,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            completed_at = excluded.completed_at,
            sort_order = excluded.sort_order,
            archived = excluded.archived,
            due_date = excluded.due_date,
            note = excluded.note,
            bug_cause = excluded.bug_cause,
            fix_plan = excluded.fix_plan,
            converted_to_optimization_id = excluded.converted_to_optimization_id,
            tags_json = excluded.tags_json,
            subtasks_json = excluded.subtasks_json,
            attachments_json = excluded.attachments_json,
            changelog_json = excluded.changelog_json;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw TodoStoreError.statementPrepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        bind(text: todo.id, to: 1, statement: statement)
        bind(text: todo.title, to: 2, statement: statement)
        bind(text: todo.category.rawValue, to: 3, statement: statement)
        bind(text: todo.priority.rawValue, to: 4, statement: statement)
        bind(text: todo.status.rawValue, to: 5, statement: statement)
        bind(text: todo.date, to: 6, statement: statement)
        bind(text: iso8601Formatter.string(from: todo.createdAt), to: 7, statement: statement)
        bind(text: iso8601Formatter.string(from: todo.updatedAt), to: 8, statement: statement)
        bind(text: todo.completedAt.map { iso8601Formatter.string(from: $0) }, to: 9, statement: statement)
        bind(int: todo.order, to: 10, statement: statement)
        bind(bool: todo.archived, to: 11, statement: statement)
        bind(text: todo.dueDate, to: 12, statement: statement)
        bind(text: todo.note, to: 13, statement: statement)
        bind(text: todo.bugCause, to: 14, statement: statement)
        bind(text: todo.fixPlan, to: 15, statement: statement)
        bind(text: todo.convertedToOptimizationId, to: 16, statement: statement)
        bind(text: encodeJSON(todo.tags), to: 17, statement: statement)
        bind(text: encodeJSON(todo.subtasks), to: 18, statement: statement)
        bind(text: encodeJSON(todo.attachments), to: 19, statement: statement)
        bind(text: encodeJSON(todo.changelog), to: 20, statement: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TodoStoreError.executeFailed(lastErrorMessage())
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? jsonEncoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, _ string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? jsonDecoder.decode(type, from: data)
    }

    private func columnExists(table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
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

    private func bind(int: Int, to index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_int64(statement, index, Int64(int))
    }

    private func bind(bool: Bool, to index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_int(statement, index, bool ? 1 : 0)
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
