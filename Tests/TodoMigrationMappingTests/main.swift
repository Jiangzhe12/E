import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

let json = """
{
  "todos": [
    {"id":"a","title":"功能X","category":"feature","priority":"high","status":"done",
     "date":"2026-04-13","createdAt":"2026-04-13T01:02:03.123Z","updatedAt":"2026-04-14T05:06:07.000Z",
     "order":2,"archived":false,
     "changelog":[{"timestamp":"2026-04-14T05:06:07.000Z","field":"status","oldValue":"待办","newValue":"已完成"}]},
    {"id":"b","title":"BugY","category":"bug","status":"pending",
     "date":"2026-04-15","createdAt":"2026-04-15T00:00:00.000Z","bugCause":"空指针","dueDate":"2026-04-20"},
    {"id":"c","title":"带子任务","category":"optimization","priority":"low","status":"pending",
     "date":"2026-04-16","subtasks":[{"id":"s1","title":"st","done":true}],"tags":["重要"],"fixPlan":"plan"}
  ],
  "lastOpenDate":"2026-04-16",
  "memo":"备忘内容",
  "memoUpdatedAt":"2026-04-16T12:00:00.000Z",
  "savedReports":{"04/13":"周报文本"},
  "windowBounds":{"x":1,"y":2}
}
"""

let result = try LegacyTodoDecoder.decode(Data(json.utf8), today: "2026-06-17")
func find(_ id: String) -> TodoItem { result.todos.first { $0.id == id }! }

expect(result.todos.count == 3, "all 3 todos decode")

let a = find("a")
expect(a.category == .feature && a.priority == .high && a.status == .done, "a enums map correctly")
expect(a.completedAt != nil, "done todo without completedAt is backfilled")
expect(a.order == 2, "explicit order preserved")
expect(a.changelog?.count == 1 && a.changelog?.first?.newValue == "已完成", "Chinese changelog preserved")

// Fractional-seconds ISO parse: createdAt must be the real date, not the fallback.
let isoFrac = ISO8601DateFormatter()
isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
expect(abs(a.createdAt.timeIntervalSince(isoFrac.date(from: "2026-04-13T01:02:03.123Z")!)) < 0.5,
       "fractional-second timestamps parse exactly")

let b = find("b")
expect(b.priority == .medium, "missing priority defaults to medium")
expect(b.status == .pending && b.completedAt == nil, "pending todo has no completedAt")
expect(b.bugCause == "空指针" && b.dueDate == "2026-04-20", "bug fields and dueDate map")
expect(b.order == 1, "missing order backfills to index")

let c = find("c")
expect(c.subtasks?.count == 1 && c.subtasks?.first?.done == true, "subtasks map")
expect(c.tags == ["重要"] && c.fixPlan == "plan", "tags and fixPlan map")
expect(c.priority == .low, "low priority maps")

expect(result.savedReports["04/13"] == "周报文本", "savedReports MM/dd keys preserved verbatim")
expect(result.memo == "备忘内容" && result.memoUpdatedAt != nil, "memo + timestamp decode")
expect(result.lastOpenDate == "2026-04-16", "lastOpenDate decodes")

print("TodoMigrationMappingTests passed")
