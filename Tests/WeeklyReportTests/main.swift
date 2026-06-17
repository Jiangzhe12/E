import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

let cal = Calendar.current

func at(_ ymd: String, hour: Int = 12) -> Date {
    let p = ymd.split(separator: "-").map { Int($0)! }
    return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
}

func makeTodo(
    id: String,
    date: String,
    category: TodoCategory = .feature,
    status: TodoStatus = .pending,
    createdAt: Date,
    completedAt: Date? = nil,
    dueDate: String? = nil
) -> TodoItem {
    TodoItem(
        id: id, title: "t-\(id)", category: category, priority: .medium,
        status: status, date: date, createdAt: createdAt, updatedAt: createdAt,
        completedAt: completedAt, order: 0, archived: false, dueDate: dueDate, note: nil,
        tags: nil, subtasks: nil, attachments: nil, changelog: nil,
        bugCause: nil, fixPlan: nil, convertedToOptimizationId: nil
    )
}

let now = at("2026-06-17")

// mondayStart must land on a Monday (weekday 2) at or before `now`.
let monday = WeeklyReport.mondayStart(of: now, calendar: cal)
expect(cal.component(.weekday, from: monday) == 2, "week starts on Monday")
expect(monday <= now, "Monday is at or before now")

let todos = [
    makeTodo(id: "c1", date: "x", status: .done, createdAt: monday.addingTimeInterval(8 * 3600),
             completedAt: monday.addingTimeInterval(10 * 3600)),                 // 2h, Monday
    makeTodo(id: "c2", date: "x", status: .done, createdAt: now.addingTimeInterval(-2 * 3600),
             completedAt: now),                                                  // 2h, today
    makeTodo(id: "ip", date: "x", status: .inProgress, createdAt: now),
    makeTodo(id: "od", date: "x", status: .pending, createdAt: now, dueDate: "2020-01-01"),
]

let report = WeeklyReport.generate(todos: todos, offset: 0, now: now, calendar: cal)

expect(report.markdown.hasPrefix("# 周报 ("), "markdown has report header")
expect(report.stats.completed == 2, "two completed this week")
expect(report.stats.created == 4, "all four todos were created this week (created counts every status)")
expect(report.stats.inProgress == 1, "one in progress")
expect(report.stats.overdue == 1, "one overdue")
expect(report.stats.completionRate == 50, "completionRate = round(2/4*100) = 50")
expect(report.stats.avgDurationText == "2h", "avg duration 2h")
expect(report.dailyCompletion.count == 7, "seven day buckets")
expect(report.dailyCompletion[0].count == 1, "Monday bucket has the Monday completion")
expect(report.dailyCompletion.contains { $0.isToday && $0.count == 1 }, "today's bucket counts today's completion")

// Past week: inProgress / overdue are not meaningful, and no completions → rate 0, avg —.
let lastWeek = WeeklyReport.generate(todos: todos, offset: -1, now: now, calendar: cal)
expect(lastWeek.stats.inProgress == 0 && lastWeek.stats.overdue == 0, "past week has no in-progress/overdue")
expect(lastWeek.stats.completionRate == 0, "empty denominator → 0% rate")
expect(lastWeek.stats.avgDurationText == "—", "no completions → em dash")

// Days threshold: a 48h-duration completion renders as "2d".
let longTodo = [makeTodo(id: "L", date: "x", status: .done,
                         createdAt: now.addingTimeInterval(-48 * 3600), completedAt: now)]
let longReport = WeeklyReport.generate(todos: longTodo, offset: 0, now: now, calendar: cal)
expect(longReport.stats.avgDurationText == "2d", "48h average renders as days")
expect(longReport.stats.completionRate == 100, "single completion, no other open → 100%")

print("WeeklyReportTests passed")
