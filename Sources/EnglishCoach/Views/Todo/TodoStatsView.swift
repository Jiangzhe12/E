import SwiftUI

/// Todo overview stats: today's progress, status counts, a 7-day completion bar
/// chart, and open-by-category distribution. `compact` drops the chart for the
/// list header; the full version is embedded in the 统计 tab.
struct TodoStatsView: View {
    @ObservedObject var model: AppModel
    var compact: Bool = false

    var body: some View {
        let stats = model.todoStats
        VStack(alignment: .leading, spacing: 12) {
            statBoxes(stats)
            if !compact {
                completionChart(stats)
                categoryDistribution(stats)
            }
        }
    }

    private func statBoxes(_ stats: TodoStats) -> some View {
        HStack(spacing: 10) {
            statBox(title: "今日完成", value: "\(stats.todayDone)/\(stats.todayTotal)", color: TodoPalette.status(.done))
            statBox(title: "进行中", value: "\(stats.inProgress)", color: TodoPalette.status(.inProgress))
            statBox(title: "待办", value: "\(stats.pending)", color: TodoPalette.title)
            statBox(title: "逾期", value: "\(stats.overdue)", color: TodoPalette.orange)
        }
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
    }

    private func completionChart(_ stats: TodoStats) -> some View {
        let maxCount = max(stats.dailyCompletion.map(\.count).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("近 7 天完成")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(stats.dailyCompletion.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        Text("\(day.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(day.count > 0 ? 1 : 0.4)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.isToday ? TodoPalette.status(.done) : TodoPalette.title.opacity(0.55))
                            .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 60))
                        Text(day.label)
                            .font(.caption2)
                            .foregroundStyle(day.isToday ? TodoPalette.title : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func categoryDistribution(_ stats: TodoStats) -> some View {
        let total = max(stats.categoryOpenCounts.reduce(0) { $0 + $1.count }, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("未完成分类分布")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(stats.categoryOpenCounts, id: \.category) { item in
                HStack(spacing: 8) {
                    Text(item.category.title)
                        .font(.caption)
                        .frame(width: 64, alignment: .leading)
                        .foregroundStyle(TodoPalette.category(item.category))
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(TodoPalette.category(item.category).opacity(0.55))
                            .frame(width: max(2, geo.size.width * CGFloat(item.count) / CGFloat(total)))
                    }
                    .frame(height: 12)
                    Text("\(item.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }
}
