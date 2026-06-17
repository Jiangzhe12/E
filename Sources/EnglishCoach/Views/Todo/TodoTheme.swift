import SwiftUI

extension Color {
    /// Builds a SwiftUI color from a model RGB tuple (keeps the model SwiftUI-free).
    init(todoRGB rgb: (red: Double, green: Double, blue: Double)) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

enum TodoPalette {
    /// Shared card title blue, matching the other detail cards.
    static let title = Color(red: 0.13, green: 0.30, blue: 0.50)
    static let orange = Color(red: 0.84, green: 0.45, blue: 0.18)

    static func category(_ category: TodoCategory) -> Color {
        Color(todoRGB: category.rgb)
    }

    static func status(_ status: TodoStatus) -> Color {
        switch status {
        case .pending: return Color.secondary
        case .inProgress: return Color(red: 0.231, green: 0.510, blue: 0.965)
        case .done: return Color(red: 0.133, green: 0.773, blue: 0.369)
        }
    }

    static func statusSymbol(_ status: TodoStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    /// Foreground / background colors for a due-date pill.
    static func due(_ kind: TodoDueKind) -> (fg: Color, bg: Color) {
        switch kind {
        case .overdue:
            return (Color(red: 0.84, green: 0.45, blue: 0.18), Color(red: 1.0, green: 0.93, blue: 0.85))
        case .today:
            return (Color(red: 0.78, green: 0.44, blue: 0.12), Color(red: 1.0, green: 0.95, blue: 0.86))
        case .soon:
            return (Color(red: 0.66, green: 0.52, blue: 0.10), Color(red: 1.0, green: 0.98, blue: 0.86))
        case .later:
            return (Color(red: 0.22, green: 0.44, blue: 0.64), Color(red: 0.90, green: 0.95, blue: 1.0))
        }
    }
}

/// Formats a "YYYY-MM-DD" group key into a friendly Chinese header.
func todoGroupHeader(for dateKey: String, today: String, calendar: Calendar = .current) -> String {
    if dateKey == today { return "今天" }
    let gap = todoDayGap(from: dateKey, to: today, calendar: calendar)
    if gap == 1 { return "昨天" }
    if gap == -1 { return "明天" }
    return String(dateKey.suffix(5))  // MM-DD
}
