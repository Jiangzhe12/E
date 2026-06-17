import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

func day(_ s: String) -> Date {
    let p = s.split(separator: "-").map { Int($0)! }
    return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
}

func makeTodo(
    id: String,
    date: String,
    category: TodoCategory = .feature,
    status: TodoStatus = .pending,
    dueDate: String? = nil,
    completedAt: Date? = nil,
    archived: Bool = false
) -> TodoItem {
    TodoItem(
        id: id, title: "t-\(id)", category: category, priority: .medium,
        status: status, date: date,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
        completedAt: completedAt, order: 0, archived: archived, dueDate: dueDate, note: nil,
        tags: nil, subtasks: nil, attachments: nil, changelog: nil,
        bugCause: nil, fixPlan: nil, convertedToOptimizationId: nil
    )
}

let today = "2026-06-17"
let now = day(today)

let todos = [
    makeTodo(id: "1", date: today, status: .done, completedAt: day("2026-06-17")),
    makeTodo(id: "2", date: today, category: .feature, status: .pending),
    makeTodo(id: "3", date: today, category: .bug, status: .inProgress),
    makeTodo(id: "4", date: today, category: .feature, status: .pending, dueDate: "2026-06-10"),
    makeTodo(id: "5", date: "2026-06-15", status: .done, completedAt: day("2026-06-15")),
    makeTodo(id: "6", date: today, status: .pending, archived: true),
]

let stats = TodoStats.compute(todos: todos, today: today, now: now)

expect(stats.dailyCompletion.count == 7, "7-day window")
expect(stats.dailyCompletion.last?.isToday == true, "last bucket is today")
expect(stats.dailyCompletion.last?.count == 1, "today completion count = 1")
expect(stats.dailyCompletion[4].count == 1, "2026-06-15 bucket (offset 2) has 1 completion")

expect(stats.todayTotal == 4, "today total excludes archived and other-day todos")
expect(stats.todayDone == 1, "one done today")
expect(stats.pending == 2, "two pending open todos")
expect(stats.inProgress == 1, "one in-progress")
expect(stats.overdue == 1, "one overdue (past dueDate, not done)")

let featureCount = stats.categoryOpenCounts.first { $0.category == .feature }?.count
let bugCount = stats.categoryOpenCounts.first { $0.category == .bug }?.count
expect(featureCount == 2 && bugCount == 1, "open category distribution")
expect(stats.categoryOpenCounts.reduce(0) { $0 + $1.count } == 3, "category counts sum to open count")

print("TodoStatsTests passed")
