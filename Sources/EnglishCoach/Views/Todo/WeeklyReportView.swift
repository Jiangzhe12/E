import AppKit
import SwiftUI

/// Weekly report: week navigator + 概览 / 明细 / 汇报 tabs. The 汇报 tab lets the
/// user edit and persist a per-week report (keyed by week-start "MM/dd").
struct WeeklyReportView: View {
    @ObservedObject var model: AppModel

    enum ReportTab: String, CaseIterable, Identifiable {
        case overview, details, report
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "概览"
            case .details: return "明细"
            case .report: return "汇报"
            }
        }
    }

    @State private var tab: ReportTab = .overview
    @State private var editorText: String = ""

    private var report: WeeklyReport { model.weeklyReport(offset: model.weeklyReportOffset) }

    var body: some View {
        let report = self.report
        return VStack(alignment: .leading, spacing: 12) {
            navigator(report)
            Picker("", selection: $tab) {
                ForEach(ReportTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .overview: overview(report)
            case .details: details(report)
            case .report: reportEditor(report)
            }
        }
        .onAppear { loadEditor(report) }
        .onChange(of: model.weeklyReportOffset) { _, _ in loadEditor(self.report) }
    }

    private func navigator(_ report: WeeklyReport) -> some View {
        HStack {
            Button { model.weeklyReportOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text("\(report.weekStart) - \(report.weekEnd)")
                .font(.headline)
                .foregroundStyle(TodoPalette.title)
            Spacer()
            Button { model.weeklyReportOffset += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(model.weeklyReportOffset >= 0)
        }
    }

    private func overview(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                reportStat("完成", "\(report.stats.completed)", TodoPalette.status(.done))
                reportStat("新增", "\(report.stats.created)", TodoPalette.title)
                reportStat("进行中", "\(report.stats.inProgress)", TodoPalette.status(.inProgress))
                reportStat("逾期", "\(report.stats.overdue)", TodoPalette.orange)
            }
            HStack(spacing: 16) {
                Text("完成率 \(report.stats.completionRate)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("平均耗时 \(report.stats.avgDurationText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            dailyBars(report)

            VStack(alignment: .leading, spacing: 4) {
                Text("亮点").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(report.highlights.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)").font(.caption).foregroundStyle(.primary)
                }
            }
        }
    }

    private func dailyBars(_ report: WeeklyReport) -> some View {
        let maxCount = max(report.dailyCompletion.map(\.count).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(report.dailyCompletion.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    Text("\(day.count)").font(.caption2).foregroundStyle(.secondary).opacity(day.count > 0 ? 1 : 0.4)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(day.isToday ? TodoPalette.status(.done) : TodoPalette.title.opacity(0.55))
                        .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 56))
                    Text(day.label).font(.caption2).foregroundStyle(day.isToday ? TodoPalette.title : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func reportStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.7)))
    }

    @ViewBuilder
    private func details(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            reportSection("本周完成 (\(report.completedList.count))", report.completedList)
            reportSection("进行中 (\(report.inProgressList.count))", report.inProgressList)
            reportSection("本周新增 (\(report.createdList.count))", report.createdList)
            if !report.overdueList.isEmpty {
                reportSection("逾期未完成 (\(report.overdueList.count))", report.overdueList)
            }
        }
    }

    private func reportSection(_ title: String, _ entries: [WeeklyReportEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if entries.isEmpty {
                Text("暂无").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 6) {
                        Text(entry.category.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TodoPalette.category(entry.category))
                        Text(entry.title).font(.caption).lineLimit(1)
                        if let sub = entry.subtasksText {
                            Text("(\(sub))").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let extra = entry.extra {
                            Text("截止 \(extra)").font(.caption2).foregroundStyle(TodoPalette.orange)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func reportEditor(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editorText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            HStack {
                Button("重新生成") { editorText = report.markdown }
                    .buttonStyle(.bordered)
                Button("保存") { model.saveWeeklyReport(weekStart: report.weekStart, text: editorText) }
                    .buttonStyle(.borderedProminent)
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editorText, forType: .string)
                }
                .buttonStyle(.bordered)
                Spacer()
                if model.savedReports[report.weekStart] != nil {
                    Button("清除已存") { model.clearSavedReport(weekStart: report.weekStart); editorText = report.markdown }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
    }

    private func loadEditor(_ report: WeeklyReport) {
        editorText = model.savedReports[report.weekStart] ?? report.markdown
    }
}
