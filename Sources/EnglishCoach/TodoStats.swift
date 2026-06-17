import Foundation

struct TodoDayCount: Equatable {
    let label: String
    let count: Int
    let isToday: Bool
}

struct TodoCategoryCount: Equatable {
    let category: TodoCategory
    let count: Int
}

/// Lightweight overview stats for the 待办 stats panel. The richer weekly-report
/// math lives separately. Pure / AppKit-free so it's unit-testable.
struct TodoStats: Equatable {
    var todayTotal: Int
    var todayDone: Int
    var pending: Int
    var inProgress: Int
    var overdue: Int
    /// Last 7 days, oldest → newest.
    var dailyCompletion: [TodoDayCount]
    var categoryOpenCounts: [TodoCategoryCount]

    var todayCompletionRate: Double {
        todayTotal == 0 ? 0 : Double(todayDone) / Double(todayTotal)
    }

    static func compute(
        todos: [TodoItem],
        today: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TodoStats {
        let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
        let active = todos.filter { !$0.archived }
        let open = active.filter { $0.status != .done }
        let todayList = active.filter { $0.date == today }

        let overdue = open.filter { todo in
            guard let due = todo.dueDate else { return false }
            return due < today
        }.count

        var buckets: [TodoDayCount] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = todoDayKey(for: day, calendar: calendar)
            let count = active.filter { todo in
                guard let completedAt = todo.completedAt else { return false }
                return todoDayKey(for: completedAt, calendar: calendar) == key
            }.count
            let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
            buckets.append(TodoDayCount(label: weekdaySymbols[(weekday - 1) % 7], count: count, isToday: key == today))
        }

        let categoryCounts = TodoCategory.allCases.map { category in
            TodoCategoryCount(category: category, count: open.filter { $0.category == category }.count)
        }

        return TodoStats(
            todayTotal: todayList.count,
            todayDone: todayList.filter { $0.status == .done }.count,
            pending: open.filter { $0.status == .pending }.count,
            inProgress: open.filter { $0.status == .inProgress }.count,
            overdue: overdue,
            dailyCompletion: buckets,
            categoryOpenCounts: categoryCounts
        )
    }
}
