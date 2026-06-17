import Foundation

/// Task category, ported 1:1 from the TodoList-zhe Electron app
/// (`feature` / `bug` / `optimization`). Raw values match the JS strings so the
/// legacy `todo-data.json` decodes directly.
enum TodoCategory: String, Codable, CaseIterable, Identifiable {
    case feature
    case bug
    case optimization

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feature: return "Feature"
        case .bug: return "Bug"
        case .optimization: return "优化"
        }
    }

    var systemImage: String {
        switch self {
        case .feature: return "sparkles"
        case .bug: return "ladybug"
        case .optimization: return "wand.and.stars"
        }
    }

    /// Badge color as an RGB tuple (kept here so the model stays SwiftUI-free
    /// and the test mains can compile it without AppKit). Mirrors the web hex:
    /// Feature #3b82f6, Bug #ef4444, 优化 #0d9488.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .feature: return (0.231, 0.510, 0.965)
        case .bug: return (0.937, 0.267, 0.267)
        case .optimization: return (0.051, 0.580, 0.533)
        }
    }
}

/// Priority, ported from the web app. `sortWeight` drives the optional
/// "sort by priority" toggle (high first).
enum TodoPriority: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }

    var sortWeight: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

/// Lifecycle status. The status toggle cycles pending → in_progress → done →
/// pending. `chineseLabel` matches the labels written into the legacy
/// changelog entries (待办 / 进行中 / 已完成), so imported history reads cleanly.
enum TodoStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case inProgress = "in_progress"
    case done

    var id: String { rawValue }

    var chineseLabel: String {
        switch self {
        case .pending: return "待办"
        case .inProgress: return "进行中"
        case .done: return "已完成"
        }
    }

    var next: TodoStatus {
        switch self {
        case .pending: return .inProgress
        case .inProgress: return .done
        case .done: return .pending
        }
    }
}

struct Subtask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var done: Bool
}

/// Append-only audit entry for a tracked-field edit.
struct ChangeLogEntry: Codable, Equatable {
    let timestamp: Date
    let field: String
    let oldValue: String?
    let newValue: String?
}

/// Fields whose edits are recorded in `changelog` (matches the web app's set).
enum TrackedField: String {
    case title
    case category
    case priority
    case status
    case dueDate
    case note
}

/// A reusable template a todo can be created from. `subtasks` stores titles
/// only; instantiation materialises them into `Subtask` values.
struct TodoTemplate: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: TodoCategory
    var priority: TodoPriority
    var tags: [String]?
    var subtasks: [String]?
    var note: String?
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var category: TodoCategory
    var priority: TodoPriority
    var status: TodoStatus
    /// Grouping/sort key, "YYYY-MM-DD". Lexicographic comparison equals
    /// chronological comparison, which carry-over and overdue checks rely on.
    var date: String
    var createdAt: Date
    var updatedAt: Date
    /// Set once on the first transition to `.done` and never cleared, so the
    /// weekly report's "completed this week" stays accurate even if a task is
    /// reopened.
    var completedAt: Date?
    /// Sort order within a date group (0 = top).
    var order: Int
    var archived: Bool
    var dueDate: String?
    var note: String?
    var tags: [String]?
    var subtasks: [Subtask]?
    var attachments: [String]?
    var changelog: [ChangeLogEntry]?
    // Bug-only fields.
    var bugCause: String?
    var fixPlan: String?
    var convertedToOptimizationId: String?

    var isBug: Bool { category == .bug }
}

/// Formats a `Date` as the "YYYY-MM-DD" day key todos are grouped by. Uses the
/// supplied calendar's timezone, matching the rest of the app's day bucketing.
func todoDayKey(for date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 1970,
        components.month ?? 1,
        components.day ?? 1
    )
}

/// How a due date relates to today, used for label text + color.
enum TodoDueKind {
    case overdue
    case today
    case soon
    case later
}

private let todoDayParser: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// Whole-day gap between two "YYYY-MM-DD" keys (0 if either can't be parsed).
func todoDayGap(from: String, to: String, calendar: Calendar = .current) -> Int {
    guard let a = todoDayParser.date(from: from), let b = todoDayParser.date(from: to) else { return 0 }
    return calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
}

/// Human-friendly due-date label, ported from the web row:
/// overdue → "逾期 X 天", today → "今天到期", within 3 days → "X 天后", else "MM-DD".
func todoDueInfo(dueDate: String?, today: String, calendar: Calendar = .current) -> (text: String, kind: TodoDueKind)? {
    guard let dueDate, !dueDate.isEmpty else { return nil }
    if dueDate < today {
        return ("逾期 \(abs(todoDayGap(from: dueDate, to: today, calendar: calendar))) 天", .overdue)
    }
    if dueDate == today {
        return ("今天到期", .today)
    }
    let days = todoDayGap(from: today, to: dueDate, calendar: calendar)
    if days <= 3 {
        return ("\(days) 天后", .soon)
    }
    return (String(dueDate.suffix(5)), .later)
}
