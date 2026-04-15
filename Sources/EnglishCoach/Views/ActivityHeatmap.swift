import SwiftUI

/// GitHub-style activity heatmap over the last `days` days.
/// Each cell is a calendar day; color intensity reflects how many activity
/// events happened (translations + learning attempts + newly mastered words).
struct ActivityHeatmap: View {
    /// Key is `yyyy-MM-dd`, value is total activity count.
    let counts: [String: Int]
    let days: Int

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    init(counts: [String: Int], days: Int = 182) {
        self.counts = counts
        self.days = days
    }

    var body: some View {
        let cells = buildCells()
        let columns = Int(ceil(Double(cells.count) / 7.0))

        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(0 ..< columns, id: \.self) { column in
                            VStack(spacing: cellSpacing) {
                                ForEach(0 ..< 7, id: \.self) { row in
                                    let index = column * 7 + row
                                    if index < cells.count {
                                        cellView(cells[index])
                                    } else {
                                        Color.clear.frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                            .id(column)
                        }
                    }
                }
                .onAppear {
                    // Defer one tick so layout has resolved before scrolling.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(max(0, columns - 1), anchor: .trailing)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("少")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0 ..< 4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(color(forLevel: level))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("多")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: DayCell) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color(forLevel: intensityLevel(for: cell.count)))
            .frame(width: cellSize, height: cellSize)
            .help("\(cell.displayDate) · \(cell.count) 次")
    }

    private struct DayCell {
        let key: String
        let date: Date
        let count: Int
        let displayDate: String
    }

    private func buildCells() -> [DayCell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Align the grid so the most recent column contains today's weekday,
        // and we fill up to 7 rows per column. Start offset aligns weekday:
        // row 0 = Sunday, row 6 = Saturday.
        let todayWeekday = calendar.component(.weekday, from: today) - 1 // 0..6
        let alignedStart = calendar.date(byAdding: .day, value: -(days - 1 + (6 - todayWeekday)), to: today) ?? today

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"

        var cells: [DayCell] = []
        cells.reserveCapacity(days)

        var cursor = alignedStart
        let total = days + (6 - todayWeekday)
        for _ in 0 ..< total {
            let components = calendar.dateComponents([.year, .month, .day], from: cursor)
            let key = String(
                format: "%04d-%02d-%02d",
                components.year ?? 1970,
                components.month ?? 1,
                components.day ?? 1
            )
            let count = counts[key] ?? 0
            cells.append(
                DayCell(
                    key: key,
                    date: cursor,
                    count: cursor > today ? -1 : count,
                    displayDate: formatter.string(from: cursor)
                )
            )
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        return cells
    }

    private func intensityLevel(for count: Int) -> Int {
        if count < 0 { return -1 }   // future (grid padding)
        if count == 0 { return 0 }
        if count <= 2 { return 1 }
        if count <= 5 { return 2 }
        return 3
    }

    private func color(forLevel level: Int) -> Color {
        switch level {
        case -1: return Color.clear
        case 0: return Color(red: 0.90, green: 0.94, blue: 0.95)
        case 1: return Color(red: 0.66, green: 0.84, blue: 0.66)
        case 2: return Color(red: 0.35, green: 0.73, blue: 0.40)
        case 3: return Color(red: 0.17, green: 0.56, blue: 0.28)
        default: return Color.gray
        }
    }
}
