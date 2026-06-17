import Foundation

struct WeeklyReportStats: Equatable {
    var completed: Int
    var created: Int
    var inProgress: Int
    var overdue: Int
    var completionRate: Int
    var avgDurationText: String
}

struct WeeklyReportDay: Equatable {
    let label: String
    let count: Int
    let isToday: Bool
}

struct WeeklyReportCategory: Equatable {
    let category: TodoCategory
    let count: Int
}

struct WeeklyReportEntry: Equatable {
    let title: String
    let category: TodoCategory
    let bugCause: String?
    let subtasksText: String?
    let extra: String?  // dueDate for overdue entries
}

/// A computed weekly report, ported 1:1 from TodoList-zhe's `generateWeeklyReport`.
struct WeeklyReport: Equatable {
    var weekStart: String   // "MM/dd"
    var weekEnd: String     // "MM/dd"
    var stats: WeeklyReportStats
    var dailyCompletion: [WeeklyReportDay]
    var byCategory: [WeeklyReportCategory]
    var completedList: [WeeklyReportEntry]
    var inProgressList: [WeeklyReportEntry]
    var createdList: [WeeklyReportEntry]
    var overdueList: [WeeklyReportEntry]
    var highlights: [String]
    var markdown: String

    static func generate(
        todos: [TodoItem],
        offset: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyReport {
        let target = calendar.date(byAdding: .day, value: offset * 7, to: now) ?? now
        let monday = mondayStart(of: target, calendar: calendar)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? target
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? target

        let weekStartStr = mmdd(monday, calendar: calendar)
        let weekEndStr = mmdd(sunday, calendar: calendar)
        let todayStr = todoDayKey(for: now, calendar: calendar)
        let isPast = offset < 0

        func inWeek(_ date: Date) -> Bool { date >= monday && date < nextMonday }

        let completed = todos.filter { $0.completedAt.map(inWeek) ?? false }
        let created = todos.filter { inWeek($0.createdAt) }
        let inProgress = isPast ? [] : todos.filter { $0.status == .inProgress && !$0.archived }
        let overdue = isPast ? [] : todos.filter {
            guard let due = $0.dueDate else { return false }
            return due < todayStr && $0.status != .done && !$0.archived
        }

        let denom = completed.count + inProgress.count + overdue.count
        let completionRate = denom > 0 ? Int((Double(completed.count) / Double(denom) * 100).rounded()) : 0

        var avgDurationText = "—"
        if !completed.isEmpty {
            let totalSeconds = completed.reduce(0.0) { sum, todo in
                sum + (todo.completedAt!.timeIntervalSince(todo.createdAt))
            }
            let avgHours = ((totalSeconds / Double(completed.count) / 3600) * 10).rounded() / 10
            if avgHours < 24 {
                avgDurationText = "\(trimNumber(avgHours))h"
            } else {
                let avgDays = ((avgHours / 24) * 10).rounded() / 10
                avgDurationText = "\(trimNumber(avgDays))d"
            }
        }

        // Daily buckets: index 0 = Mon … 6 = Sun, by day-offset from Monday.
        let mondayDayStart = calendar.startOfDay(for: monday)
        var dailyCounts = [Int](repeating: 0, count: 7)
        for todo in completed {
            guard let completedAt = todo.completedAt else { continue }
            let dayStart = calendar.startOfDay(for: completedAt)
            let dayOffset = calendar.dateComponents([.day], from: mondayDayStart, to: dayStart).day ?? -1
            if dayOffset >= 0 && dayOffset <= 6 {
                dailyCounts[dayOffset] += 1
            }
        }
        let todayOffset = calendar.dateComponents([.day], from: mondayDayStart, to: calendar.startOfDay(for: now)).day ?? -1
        let dayLabels = ["一", "二", "三", "四", "五", "六", "日"]
        let dailyCompletion = (0..<7).map { idx in
            WeeklyReportDay(label: dayLabels[idx], count: dailyCounts[idx], isToday: idx == todayOffset)
        }

        let byCategory = TodoCategory.allCases.map { category in
            WeeklyReportCategory(category: category, count: completed.filter { $0.category == category }.count)
        }

        func subtasksText(_ todo: TodoItem) -> String? {
            guard let subtasks = todo.subtasks, !subtasks.isEmpty else { return nil }
            return "\(subtasks.filter(\.done).count)/\(subtasks.count)"
        }

        let completedList = completed
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .map { WeeklyReportEntry(title: $0.title, category: $0.category, bugCause: $0.isBug ? $0.bugCause : nil, subtasksText: subtasksText($0), extra: nil) }
        let inProgressList = inProgress.map {
            WeeklyReportEntry(title: $0.title, category: $0.category, bugCause: nil, subtasksText: subtasksText($0), extra: nil)
        }
        let createdList = created.map {
            WeeklyReportEntry(title: $0.title, category: $0.category, bugCause: nil, subtasksText: nil, extra: nil)
        }
        let overdueList = overdue.map {
            WeeklyReportEntry(title: $0.title, category: $0.category, bugCause: nil, subtasksText: nil, extra: $0.dueDate)
        }

        let stats = WeeklyReportStats(
            completed: completed.count, created: created.count, inProgress: inProgress.count,
            overdue: overdue.count, completionRate: completionRate, avgDurationText: avgDurationText
        )

        let highlights = buildHighlights(stats: stats, dailyCounts: dailyCounts, byCategory: byCategory)
        let markdown = buildMarkdown(
            weekStart: weekStartStr, weekEnd: weekEndStr, stats: stats, highlights: highlights,
            dailyCompletion: dailyCompletion, byCategory: byCategory,
            completedList: completedList, inProgressList: inProgressList,
            createdList: createdList, overdueList: overdueList
        )

        return WeeklyReport(
            weekStart: weekStartStr, weekEnd: weekEndStr, stats: stats,
            dailyCompletion: dailyCompletion, byCategory: byCategory,
            completedList: completedList, inProgressList: inProgressList,
            createdList: createdList, overdueList: overdueList,
            highlights: highlights, markdown: markdown
        )
    }

    // MARK: - Helpers

    static func mondayStart(of date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay) // 1 = Sun … 7 = Sat
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
    }

    private static func mmdd(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d/%02d", c.month ?? 1, c.day ?? 1)
    }

    private static func trimNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func buildHighlights(
        stats: WeeklyReportStats,
        dailyCounts: [Int],
        byCategory: [WeeklyReportCategory]
    ) -> [String] {
        if stats.completed == 0 && stats.created == 0 {
            return ["本周尚无任务活动，加把劲吧 💪"]
        }
        var h = ["本周完成 \(stats.completed) 项任务，新增 \(stats.created) 项"]

        if stats.completed > 0 {
            var bestIdx = -1
            var bestCount = 0
            for (idx, count) in dailyCounts.enumerated() where count > bestCount {
                bestCount = count
                bestIdx = idx
            }
            if bestIdx >= 0 && bestCount >= 2 {
                let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
                h.append("效率最高: \(dayNames[bestIdx])（\(bestCount) 项）")
            }
        }

        if let top = byCategory.filter({ $0.count > 0 }).max(by: { $0.count < $1.count }), top.count >= 2 {
            h.append("主攻方向: \(top.category.title)（\(top.count) 项）")
        }

        if stats.completionRate >= 80 {
            h.append("完成率 \(stats.completionRate)%，表现优秀 👍")
        } else if stats.completionRate >= 50 {
            h.append("完成率 \(stats.completionRate)%，稳步推进")
        } else if stats.completed + stats.inProgress >= 3 {
            h.append("完成率 \(stats.completionRate)%，建议聚焦收尾")
        }

        if stats.overdue > 0 {
            h.append("⚠️ 逾期 \(stats.overdue) 项，需优先处理")
        }
        if stats.avgDurationText != "—" {
            h.append("平均耗时 \(stats.avgDurationText)")
        }
        return h
    }

    private static func buildMarkdown(
        weekStart: String, weekEnd: String, stats: WeeklyReportStats, highlights: [String],
        dailyCompletion: [WeeklyReportDay], byCategory: [WeeklyReportCategory],
        completedList: [WeeklyReportEntry], inProgressList: [WeeklyReportEntry],
        createdList: [WeeklyReportEntry], overdueList: [WeeklyReportEntry]
    ) -> String {
        var md = "# 周报 (\(weekStart) - \(weekEnd))\n\n"
        md += "## 亮点\n"
        md += highlights.map { "- \($0)" }.joined(separator: "\n") + "\n\n"

        md += "## 统计\n"
        md += "- 完成: **\(stats.completed)** 项 · 新增: **\(stats.created)** 项 · 进行中: **\(stats.inProgress)** 项 · 逾期: **\(stats.overdue)** 项\n"
        md += "- 完成率: **\(stats.completionRate)%** · 平均耗时: **\(stats.avgDurationText)**\n\n"

        md += "## 每日完成分布\n"
        for day in dailyCompletion {
            let bar = day.count > 0 ? String(repeating: "█", count: day.count) : "·"
            md += "- 周\(day.label) `\(bar)` \(day.count)\(day.isToday ? " (今天)" : "")\n"
        }
        md += "\n"

        let nonZeroCats = byCategory.filter { $0.count > 0 }
        if !nonZeroCats.isEmpty {
            md += "## 分类分布\n"
            for cat in nonZeroCats {
                md += "- \(cat.category.title): \(cat.count) 项\n"
            }
            md += "\n"
        }

        md += "## 本周完成 (\(completedList.count))\n"
        if completedList.isEmpty {
            md += "- *暂无*\n"
        } else {
            for entry in completedList {
                var line = "- **[\(entry.category.title)]** \(entry.title)"
                if let cause = entry.bugCause, !cause.isEmpty { line += " — 原因: \(cause)" }
                if let sub = entry.subtasksText { line += " (子任务: \(sub))" }
                md += line + "\n"
            }
        }
        md += "\n"

        md += "## 进行中 (\(inProgressList.count))\n"
        if inProgressList.isEmpty {
            md += "- *暂无*\n"
        } else {
            for entry in inProgressList {
                var line = "- **[\(entry.category.title)]** \(entry.title)"
                if let sub = entry.subtasksText { line += " (子任务: \(sub))" }
                md += line + "\n"
            }
        }
        md += "\n"

        md += "## 本周新增 (\(createdList.count))\n"
        if createdList.isEmpty {
            md += "- *暂无*\n"
        } else {
            for entry in createdList.prefix(15) {
                md += "- **[\(entry.category.title)]** \(entry.title)\n"
            }
            if createdList.count > 15 {
                md += "- ...及其他 \(createdList.count - 15) 项\n"
            }
        }
        md += "\n"

        if !overdueList.isEmpty {
            md += "## 逾期未完成 (\(overdueList.count))\n"
            for entry in overdueList {
                md += "- \(entry.title) (截止: \(entry.extra ?? ""))\n"
            }
            md += "\n"
        }

        return md
    }
}
