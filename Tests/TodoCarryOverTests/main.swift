import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

func makeTodo(
    id: String,
    date: String,
    status: TodoStatus = .pending,
    archived: Bool = false
) -> TodoItem {
    TodoItem(
        id: id, title: "t-\(id)", category: .feature, priority: .medium,
        status: status, date: date,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
        completedAt: nil, order: 0, archived: archived, dueDate: nil, note: nil,
        tags: nil, subtasks: nil, attachments: nil, changelog: nil,
        bugCause: nil, fixPlan: nil, convertedToOptimizationId: nil
    )
}

let today = "2026-06-17"
let input = [
    makeTodo(id: "pastDone", date: "2026-06-10", status: .done),
    makeTodo(id: "pastOpen", date: "2026-06-10", status: .pending),
    makeTodo(id: "archivedPast", date: "2026-05-30", status: .done, archived: true),
    makeTodo(id: "todayOpen", date: "2026-06-17", status: .pending),
    makeTodo(id: "futureOpen", date: "2026-06-20", status: .pending),
]

let result = TodoCarryOver.apply(input, today: today)
func find(_ id: String) -> TodoItem { result.first { $0.id == id }! }

expect(find("pastDone").archived, "past completed todo should be auto-archived")
expect(find("pastDone").date == "2026-06-10", "auto-archiving must not change the date")

expect(!find("pastOpen").archived, "past incomplete todo stays unarchived")
expect(find("pastOpen").date == today, "past incomplete todo carries forward to today")

expect(find("archivedPast").archived, "already-archived todo stays archived")
expect(find("archivedPast").date == "2026-05-30", "already-archived todo is untouched")

expect(find("todayOpen").date == "2026-06-17", "today's todo is untouched")
expect(find("futureOpen").date == "2026-06-20", "future todo is untouched")

// Month-boundary lexicographic comparison: "2026-05-31" < "2026-06-01".
let boundary = TodoCarryOver.apply(
    [makeTodo(id: "x", date: "2026-05-31", status: .pending)],
    today: "2026-06-01"
)
expect(boundary[0].date == "2026-06-01", "carry-over compares date strings across month boundary")

print("TodoCarryOverTests passed")
