import SwiftUI

extension Color {
    /// Builds a SwiftUI color from a model RGB tuple (keeps the model SwiftUI-free).
    init(todoRGB rgb: (red: Double, green: Double, blue: Double)) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

enum TodoPalette {
    /// Shared card title blue, matching the other detail cards.
    static let title = AppColor.title
    static let orange = AppColor.warning

    static func category(_ category: TodoCategory) -> Color {
        // Light = the model's brand RGB; dark = a brightened variant so the color stays
        // legible as text / chips on dark cards (the raw RGB is tuned for light backgrounds).
        let light = Color(todoRGB: category.rgb)
        let dark: Color
        switch category {
        case .feature: dark = Color(red: 0.45, green: 0.66, blue: 1.0)
        case .bug: dark = Color(red: 1.0, green: 0.45, blue: 0.45)
        case .optimization: dark = Color(red: 0.30, green: 0.82, blue: 0.74)
        }
        return Color(light: light, dark: dark)
    }

    static func status(_ status: TodoStatus) -> Color {
        switch status {
        case .pending: return Color.secondary
        case .inProgress: return AppColor.accent
        case .done: return AppColor.success
        }
    }

    static func statusSymbol(_ status: TodoStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }

    /// Foreground / background colors for a due-date pill. A red → orange → yellow → blue
    /// ladder so the four urgency tiers read distinctly; background is the same hue at low
    /// alpha so it adapts to light/dark automatically.
    static func due(_ kind: TodoDueKind) -> (fg: Color, bg: Color) {
        let fg: Color
        switch kind {
        case .overdue: fg = AppColor.danger     // 逾期 → 红
        case .today: fg = AppColor.warning       // 今天 → 橙
        case .soon: fg = AppColor.caution        // 即将 → 黄
        case .later: fg = AppColor.subtitle      // 以后 → 蓝（中性）
        }
        return (fg, fg.opacity(0.16))
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
