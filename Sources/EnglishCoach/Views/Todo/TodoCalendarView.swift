import SwiftUI

/// Month calendar for todos: a 7-column Sunday-start grid with per-day category
/// dots, plus the selected day's todo list below. Tap a day to inspect it.
struct TodoCalendarView: View {
    @ObservedObject var model: AppModel
    let onEdit: (TodoItem) -> Void

    @State private var monthAnchor = Date()
    @State private var selectedDay: String?

    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    private var todosByDate: [String: [TodoItem]] {
        Dictionary(grouping: model.todos.filter { !$0.archived }, by: { $0.date })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            monthHeader
            weekdayHeader
            grid
            if let selectedDay {
                selectedDayList(selectedDay)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(TodoPalette.title)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = todoDayKey(for: date, calendar: calendar)
        let dayTodos = todosByDate[key] ?? []
        let categories = Array(Set(dayTodos.map(\.category))).sorted { $0.rawValue < $1.rawValue }
        let isToday = key == todoDayKey(for: Date(), calendar: calendar)
        let isSelected = key == selectedDay

        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isToday ? TodoPalette.title : Color.clear))
            HStack(spacing: 2) {
                ForEach(categories.prefix(3), id: \.self) { category in
                    Circle().fill(TodoPalette.category(category)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? TodoPalette.title.opacity(0.14) : Color.white.opacity(0.45))
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = (selectedDay == key) ? nil : key }
    }

    private func selectedDayList(_ key: String) -> some View {
        let dayTodos = (todosByDate[key] ?? []).sorted { $0.order < $1.order }
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(key.suffix(5)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if dayTodos.isEmpty {
                Text("这一天没有待办").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(dayTodos) { todo in
                    Button { onEdit(todo) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: TodoPalette.statusSymbol(todo.status))
                                .foregroundStyle(TodoPalette.status(todo.status))
                            Text(todo.title)
                                .font(.callout)
                                .strikethrough(todo.status == .done, color: .secondary)
                                .foregroundStyle(todo.status == .done ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Circle().fill(TodoPalette.category(todo.category)).frame(width: 6, height: 6)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        let firstOfMonth = interval.start
        let leadingBlanks = calendar.component(.weekday, from: firstOfMonth) - 1  // Sunday-start
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: day, to: firstOfMonth))
        }
        return cells
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: monthAnchor)
    }

    private func shiftMonth(_ delta: Int) {
        if let newAnchor = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = newAnchor
        }
    }
}
