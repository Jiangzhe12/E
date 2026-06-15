import Foundation

enum MasteredWordListScope: String, CaseIterable, Identifiable {
    case today
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
        case .all: return "全部"
        }
    }
}

struct MasteredWordListSection: Identifiable {
    let id: String
    let title: String
    let items: [MasteredWordListItem]
}

enum MasteredWordListPresentation {
    static func filteredItems(
        _ items: [MasteredWordListItem],
        scope: MasteredWordListScope,
        searchText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MasteredWordListItem] {
        let scopedItems: [MasteredWordListItem]
        switch scope {
        case .today:
            scopedItems = items.filter { calendar.isDate($0.masteredAt, inSameDayAs: now) }
        case .all:
            scopedItems = items
        }

        let query = searchText.normalizedForLookup
        guard !query.isEmpty else { return scopedItems }

        return scopedItems.filter { item in
            [
                item.word,
                item.phonetic,
                item.translation,
                item.definition
            ]
            .compactMap { $0?.normalizedForLookup }
            .contains { $0.contains(query) }
        }
    }

    static func sections(
        for items: [MasteredWordListItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MasteredWordListSection] {
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.masteredAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            let dayItems = (grouped[day] ?? []).sorted { first, second in
                if first.masteredAt == second.masteredAt {
                    return first.word < second.word
                }
                return first.masteredAt > second.masteredAt
            }
            return MasteredWordListSection(
                id: dayKey(for: day, calendar: calendar),
                title: "\(dayTitle(for: day, now: now, calendar: calendar)) · \(dayItems.count) 个",
                items: dayItems
            )
        }
    }

    static func emptyTitle(
        scope: MasteredWordListScope,
        hasAnyItems: Bool,
        isSearching: Bool
    ) -> String {
        if isSearching {
            return "没有匹配的单词"
        }
        switch scope {
        case .today:
            return hasAnyItems ? "今天还没有熟悉单词" : "还没有已熟悉单词"
        case .all:
            return "还没有已熟悉单词"
        }
    }

    static func masteredTimeText(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        "熟悉：\(friendlyDateTime(for: date, now: now, calendar: calendar))"
    }

    static func reviewText(
        for item: MasteredWordListItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard !item.isGraduated else {
            return "已完成全部复习"
        }
        guard let nextReviewDue = item.nextReviewDue else {
            return "等待复习"
        }
        if nextReviewDue <= now {
            return "待复习"
        }
        return "下次复习：\(friendlyDateTime(for: nextReviewDue, now: now, calendar: calendar))"
    }

    private static func dayTitle(
        for day: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "今天"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "昨天"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: day)
    }

    private static func friendlyDateTime(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"

        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(timeFormatter.string(from: date))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "明天 \(timeFormatter.string(from: date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(timeFormatter.string(from: date))"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func dayKey(for day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}
