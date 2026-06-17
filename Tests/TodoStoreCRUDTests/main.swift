import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

func makeTodo(id: String, date: String, status: TodoStatus = .pending) -> TodoItem {
    TodoItem(
        id: id, title: "t-\(id)", category: .feature, priority: .medium,
        status: status, date: date,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
        completedAt: nil, order: 0, archived: false, dueDate: nil, note: nil,
        tags: nil, subtasks: nil, attachments: nil, changelog: nil,
        bugCause: nil, fixPlan: nil, convertedToOptimizationId: nil
    )
}

let tmp = FileManager.default.temporaryDirectory
let dbURL = tmp.appendingPathComponent("todo-store-test-\(UUID().uuidString).sqlite3")
defer { try? FileManager.default.removeItem(at: dbURL) }

let store = try TodoStore(databaseURL: dbURL)

// Round-trip including JSON columns.
let now = Date(timeIntervalSince1970: 1_700_000_000)
var todo = TodoItem(
    id: "1", title: "测试", category: .bug, priority: .high, status: .inProgress,
    date: "2026-06-17", createdAt: now, updatedAt: now, completedAt: nil, order: 0,
    archived: false, dueDate: "2026-06-20", note: "n", tags: ["x", "y"],
    subtasks: [Subtask(id: "s", title: "sub", done: false)], attachments: nil,
    changelog: [ChangeLogEntry(timestamp: now, field: "status", oldValue: "待办", newValue: "进行中")],
    bugCause: "原因", fixPlan: nil, convertedToOptimizationId: nil
)
try store.upsert(todo)

var all = try store.fetchAll()
expect(all.count == 1, "one row stored")
let r = all[0]
expect(r.title == "测试" && r.category == .bug && r.priority == .high && r.status == .inProgress, "scalars round-trip")
expect(r.tags == ["x", "y"], "tags JSON column round-trips")
expect(r.subtasks?.first?.title == "sub", "subtasks JSON column round-trips")
expect(r.changelog?.first?.newValue == "进行中", "changelog JSON column round-trips")
expect(r.dueDate == "2026-06-20" && r.bugCause == "原因", "optional columns round-trip")

// completedAt round-trips and is not lost on a later status edit (caller keeps it).
todo.status = .done
todo.completedAt = now
try store.upsert(todo)
todo.status = .pending
try store.upsert(todo)
all = try store.fetchAll()
expect(all[0].completedAt != nil, "completedAt persists across status edits")

// Key/value store.
try store.saveString("k", "v")
expect(try store.loadString("k") == "v", "kv string round-trip")
try store.saveCustomTags(["a", "b"])
expect(try store.loadCustomTags() == ["a", "b"], "kv JSON round-trip")
try store.saveString("k", nil)
expect(try store.loadString("k") == nil, "kv delete via nil value")

// Bulk delete.
try store.deleteMany(ids: ["1"])
expect(try store.fetchAll().isEmpty, "deleteMany removes rows")

// Carry-over persistence.
try store.upsert(makeTodo(id: "p", date: "2000-01-01"))
let carried = try store.runCarryOver(today: "2026-06-17")
expect(carried.first { $0.id == "p" }?.date == "2026-06-17", "runCarryOver carries forward")
expect(try store.fetchAll().first { $0.id == "p" }?.date == "2026-06-17", "carry-over persisted")

// Legacy import idempotency.
let legacyURL = tmp.appendingPathComponent("legacy-\(UUID().uuidString).json")
defer { try? FileManager.default.removeItem(at: legacyURL) }
let legacyJSON = """
{"todos":[{"id":"L1","title":"导入","category":"feature","status":"pending","date":"2026-06-17","createdAt":"2026-06-17T00:00:00.000Z"}],"lastOpenDate":"2026-06-17"}
"""
try legacyJSON.write(to: legacyURL, atomically: true, encoding: .utf8)
let n1 = try store.importLegacyDataIfNeeded(from: legacyURL, today: "2026-06-17")
expect(n1 == 1, "first import returns imported count")
let n2 = try store.importLegacyDataIfNeeded(from: legacyURL, today: "2026-06-17")
expect(n2 == 0, "second import is a no-op (idempotent)")
expect(try store.fetchAll().filter { $0.id == "L1" }.count == 1, "no duplicate import")

print("TodoStoreCRUDTests passed")
