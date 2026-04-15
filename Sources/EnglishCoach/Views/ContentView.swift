import AppKit
import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case translate
    case stats
    case words
    case interest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .translate: return "翻译"
        case .stats: return "统计"
        case .words: return "单词"
        case .interest: return "兴趣"
        }
    }

    var systemImage: String {
        switch self {
        case .translate: return "character.book.closed"
        case .stats: return "chart.bar.xaxis"
        case .words: return "text.book.closed"
        case .interest: return "lightbulb"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    @State private var selectedTab: DetailTab = .translate
    @State private var selectedHistoryID: Int64?
    @State private var hoveredHistoryID: Int64?
    @State private var isShowingMasteredWordsSheet: Bool = false
    @State private var masteredWordSearchText: String = ""
    @State private var dailyWordRevealState = DailyWordTranslationRevealState()
    @State private var didPerformInitialActivation: Bool = false
    @State private var pendingHistoryDeletion: [Int64] = []
    @State private var isShowingHistoryDeleteConfirm: Bool = false
    @State private var didConfigureFrameAutosave: Bool = false
    @State private var isShowingShortcutHelp: Bool = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.96, blue: 0.99),
                    Color(red: 0.89, green: 0.95, blue: 0.99),
                    Color(red: 0.93, green: 0.97, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            if !didPerformInitialActivation {
                didPerformInitialActivation = true
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            if !didConfigureFrameAutosave,
               let window = NSApp.windows.first(where: { $0.title == "English Coach" }) {
                window.setFrameAutosaveName("EnglishCoach.MainWindow")
                didConfigureFrameAutosave = true
            }
        }
        .onChange(of: selectedHistoryID) { _, id in
            guard let id,
                  let item = model.history.first(where: { $0.id == id }) else {
                return
            }
            model.showHistoryItem(item)
        }
        .sheet(isPresented: $isShowingMasteredWordsSheet) {
            masteredWordsSheet
        }
        .sheet(isPresented: $isShowingShortcutHelp) {
            ShortcutHelpView {
                isShowingShortcutHelp = false
            }
        }
        .confirmationDialog(
            historyDeleteConfirmTitle,
            isPresented: $isShowingHistoryDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                commitPendingHistoryDeletion()
            }
            Button("取消", role: .cancel) {
                pendingHistoryDeletion = []
            }
        } message: {
            Text("删除后无法恢复，确定要删除这 \(pendingHistoryDeletion.count) 条历史记录吗？")
        }
    }

    private var historyDeleteConfirmTitle: String {
        pendingHistoryDeletion.count == 1
            ? "确认删除这条历史记录？"
            : "确认删除选中的历史记录？"
    }

    private func requestDeleteHistory(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        pendingHistoryDeletion = ids
        isShowingHistoryDeleteConfirm = true
    }

    private func commitPendingHistoryDeletion() {
        let ids = pendingHistoryDeletion
        pendingHistoryDeletion = []
        guard !ids.isEmpty else { return }
        if let selectedHistoryID, ids.contains(selectedHistoryID) {
            self.selectedHistoryID = nil
        }
        model.deleteHistory(ids: ids)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("学习记录")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Button {
                    Task {
                        await model.refreshHistory()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                        .padding(8)
                        .background(Color.white.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .help("刷新")
            }

            Picker("", selection: $model.historyTimeFilter) {
                ForEach(HistoryTimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("搜索单词、翻译或来源 App（⌘F）", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)

            historyList

            Text("提示：把鼠标移动到历史项上，会显示删除图标。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)

            Button("") {
                isShowingShortcutHelp = true
            }
            .keyboardShortcut("?", modifiers: [.shift])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                )
        )
        .padding(.leading, 12)
        .padding(.vertical, 12)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            detailTabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusBanner
                    switch selectedTab {
                    case .translate:
                        manualCard
                        translationCard
                    case .stats:
                        statsOverviewCard
                        activityHeatmapCard
                    case .words:
                        wordLearningCard
                    case .interest:
                        interestLearningCard
                    }
                }
                .padding(24)
            }
        }
    }

    private var detailTabBar: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                Label(tab.label, systemImage: tab.systemImage)
                    .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(
                        selectedTab == tab
                            ? Color(red: 0.13, green: 0.30, blue: 0.50)
                            : .secondary
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedTab == tab ? Color.white.opacity(0.72) : Color.clear)
                    )
                    .onTapGesture {
                        selectedTab = tab
                    }
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.25))
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !model.hasAccessibilityPermission {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color(red: 0.78, green: 0.44, blue: 0.12))
                    .help("辅助功能未授权 — 在 设置 (⌘,) 中配置")
            }
            if model.pendingRetry {
                Button {
                    Task { await model.retryLastTranslation() }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(red: 0.92, green: 0.55, blue: 0.18))
                .help("重试上一次失败的翻译")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
    }

    private var statsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("统计总览", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Text("今日")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                streakChip
                statChip(
                    title: "翻译次数",
                    value: "\(model.todayTranslationCount)",
                    systemImage: "text.book.closed"
                )
                statChip(
                    title: "兴趣学习",
                    value: "\(model.todayLearningAttemptCount)",
                    systemImage: "list.bullet.clipboard"
                )
                statChip(
                    title: "今日答对",
                    value: "\(model.todayLearningCorrectCount)",
                    systemImage: "checkmark.seal"
                )
                statChip(
                    title: "今日错题",
                    value: "\(model.todayLearningWrongCount)",
                    systemImage: "exclamationmark.triangle"
                )
            }

            HStack(spacing: 10) {
                statChip(
                    title: "今日单词",
                    value: "\(model.todayWordDeckCount)",
                    systemImage: "rectangle.3.group.bubble"
                )
                statChip(
                    title: "今日熟悉",
                    value: "\(model.todayMasteredWordCount)",
                    systemImage: "checkmark.circle"
                )
                Button {
                    isShowingMasteredWordsSheet = true
                } label: {
                    statChip(
                        title: "累计熟悉",
                        value: "\(model.totalMasteredWordCount)",
                        systemImage: "checklist.checked"
                    )
                }
                .buttonStyle(.plain)
            }

            Text(model.wordBankScaleDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("今日翻译内容")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.34, blue: 0.53))

                if model.todayTranslationItems.isEmpty {
                    Text("今天还没有翻译内容，选中句子后连续复制两次即可记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.todayTranslationItems.prefix(4))) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "dot.circle")
                                .font(.caption2)
                                .foregroundStyle(Color(red: 0.45, green: 0.63, blue: 0.82))
                            Text(item.rawText)
                                .font(.caption)
                                .lineLimit(1)
                            Text("→")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.translation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
        )
    }

    private var activityHeatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("活跃度日历", systemImage: "square.grid.3x3")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Text("过去 26 周")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ActivityHeatmap(counts: model.dailyActivityCounts)

            Text("翻译、兴趣学习、新标记熟悉都会计入当天的活跃度。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
        )
    }

    private var wordLearningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("每日单词学习", systemImage: "text.book.closed")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Text(model.dailyWordProgressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let card = model.currentDailyWordCard {
                let isRevealed = dailyWordRevealState.isRevealed(for: card.id)

                VStack(alignment: .leading, spacing: 8) {
                    if card.isReview {
                        Label("复习", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.84, green: 0.45, blue: 0.18))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(red: 1.0, green: 0.93, blue: 0.85))
                            )
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(card.word)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.21, blue: 0.36))
                        Button {
                            model.speak(card.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("p", modifiers: .command)
                        .help("朗读单词（⌘P）")
                    }

                    if let phonetic = card.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if isRevealed {
                        Text(card.meaning)
                            .font(.callout.weight(.medium))
                    } else {
                        Text("翻译已隐藏 —— 按空格或点击按钮可显示 / 再次隐藏")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(card.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("例句：\(card.example)")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.27, green: 0.40, blue: 0.55))
                        .lineLimit(3)
                    Text("词义来源：\(card.provider)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.80))
                )

                HStack(spacing: 10) {
                    Button {
                        dailyWordRevealState.toggle(for: card.id)
                    } label: {
                        Label(
                            isRevealed ? "再次隐藏" : "显示翻译",
                            systemImage: isRevealed ? "eye.slash" : "eye"
                        )
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(isRevealed ? "再次隐藏翻译（空格）" : "显示翻译（空格）")

                    if card.isReview {
                        Button {
                            model.rememberCurrentWord()
                        } label: {
                            Label("还记得", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.30, green: 0.70, blue: 0.40))
                        .keyboardShortcut("r", modifiers: [])
                        .help("还记得（R）")

                        Button {
                            model.forgotCurrentWord()
                        } label: {
                            Label("忘了", systemImage: "arrow.counterclockwise.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.84, green: 0.45, blue: 0.18))
                        .keyboardShortcut("f", modifiers: [])
                        .help("忘了（F）")
                    } else {
                        Button {
                            model.markCurrentWordAsMastered()
                        } label: {
                            Label(card.isMastered ? "已熟悉" : "标记熟悉", systemImage: card.isMastered ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(card.isMastered)
                        .keyboardShortcut("d", modifiers: .command)
                        .help("标记为已熟悉（⌘D），明天起进入复习计划")
                    }

                    Button {
                        model.showPreviousDailyWord()
                    } label: {
                        Label("上一个", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("上一个单词（←）")

                    Button {
                        model.showNextDailyWord()
                    } label: {
                        Label("下一个", systemImage: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("下一个单词（→）")

                    Spacer(minLength: 0)

                    Button("查看累计熟悉") {
                        isShowingMasteredWordsSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天可学习的单词已经全部熟悉")
                        .font(.callout.weight(.semibold))
                    Text("你可以在累计熟悉里取消熟悉，或等下一批解锁。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Self.timeUntilNextDailyBatchDescription())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.80))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
        )
    }

    private static func timeUntilNextDailyBatchDescription() -> String {
        let calendar = Calendar.current
        let now = Date()
        guard let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return "明天继续新的 20 词"
        }

        let seconds = Int(nextMidnight.timeIntervalSince(now))
        let totalMinutes = max(0, seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "距下一批解锁还有约 \(hours) 小时 \(minutes) 分"
        }
        return "距下一批解锁还有约 \(minutes) 分"
    }

    private func statChip(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(Color(red: 0.21, green: 0.43, blue: 0.61))
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.78))
        )
    }

    /// A flame-colored chip that stands out from the neutral stats — the
    /// streak is the one number worth looking at every day.
    private var streakChip: some View {
        let days = model.currentStreakDays
        return VStack(alignment: .leading, spacing: 5) {
            Label("连续", systemImage: "flame.fill")
                .font(.caption)
                .foregroundStyle(Color(red: 0.88, green: 0.45, blue: 0.12))
            Text("\(days) 天")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.28, blue: 0.08))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.82),
                            Color(red: 1.0, green: 0.88, blue: 0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .help(days > 0
            ? "已连续学习 \(days) 天，加油保持"
            : "今天还没有任何学习记录，快翻译一段或过一个单词吧")
    }

    private var masteredWordsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                TextField("搜索已熟悉单词", text: $masteredWordSearchText)
                    .textFieldStyle(.roundedBorder)

                if filteredMasteredWords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.allMasteredWords.isEmpty ? "还没有已熟悉单词" : "没有匹配的单词")
                            .font(.headline)
                        Text("在软件内“每日单词学习”里点击“标记熟悉”后会出现在这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    List {
                        ForEach(filteredMasteredWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(.body.monospaced())
                                Spacer()
                                Button("取消熟悉") {
                                    model.unmarkMasteredWord(word)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(16)
            .navigationTitle("累计熟悉单词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        isShowingMasteredWordsSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var filteredMasteredWords: [String] {
        let query = masteredWordSearchText.normalizedForLookup
        guard !query.isEmpty else { return model.allMasteredWords }
        return model.allMasteredWords.filter { $0.contains(query) }
    }

    private var historyList: some View {
        ZStack {
            List {
                ForEach(model.filteredHistory) { item in
                    historyRowView(for: item)
                }
                .onDelete(perform: deleteFromFiltered)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            if model.filteredHistory.isEmpty {
                let isFiltering = !model.searchText.trimmed.isEmpty
                    || model.historyTimeFilter != .all
                VStack(spacing: 8) {
                    Image(systemName: isFiltering ? "magnifyingglass" : "book.closed")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(isFiltering ? "未找到匹配记录" : "还没有记录")
                        .font(.headline)
                    Text(isFiltering
                         ? "换个关键词或切回「全部」试试"
                         : "先在其他应用连续复制两次（⌘C, ⌘C）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("手动输入")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Picker("", selection: $model.manualDirectionChoice) {
                    ForEach(TranslationDirectionChoice.allCases) { choice in
                        Text(choice.displayLabel).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            HStack(spacing: 10) {
                TextField("输入单词或句子（回车翻译）", text: $model.manualInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.translateFromManualInput()
                    }
                    .onExitCommand {
                        model.manualInput = ""
                    }

                Button("翻译") {
                    model.translateFromManualInput()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.57, green: 0.76, blue: 0.95))
                .disabled(model.manualInput.trimmed.isEmpty || model.isTranslating)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private var interestLearningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("兴趣学习")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Label("今日 \(model.todayLearningAttemptCount)", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
                if model.currentLessonIsReview {
                    Label("错题回刷", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.84, green: 0.41, blue: 0.15))
                }
                Label("累计 \(model.completedLearningCards)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.14, green: 0.42, blue: 0.62))
                Label("连胜 \(model.learningStreakDays) 天", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.89, green: 0.46, blue: 0.19))
            }

            HStack(spacing: 10) {
                Text("主题")
                    .font(.callout.weight(.medium))
                Picker(
                    "主题",
                    selection: Binding(
                        get: { model.selectedTopic },
                        set: { model.selectInterestTopic($0) }
                    )
                ) {
                    ForEach(InterestTopic.allCases) { topic in
                        Text(topic.title).tag(topic)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("下一题") {
                    model.refreshCurrentLesson()
                }
                .buttonStyle(.bordered)
                .help("换下一题（保留当前反馈）")
            }

            if model.isCurrentTopicExhausted {
                Label("当前主题题目已全部答对，正确题将不再刷新。可切换主题继续。", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.17, green: 0.43, blue: 0.27))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(red: 0.89, green: 0.97, blue: 0.91))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.currentLesson.title)
                    .font(.headline)
                Text(model.currentLesson.warmup)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)

            Text(model.currentLesson.passage)
                .font(.body)
                .lineSpacing(4)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.8))
                )
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                Text("关键词")
                    .font(.subheadline.weight(.semibold))
                ForEach(model.currentLesson.phrases) { phrase in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(phrase.english) · \(phrase.chinese)")
                            .font(.callout.weight(.medium))
                        Text(phrase.example)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(model.currentLesson.question)
                    .font(.subheadline.weight(.semibold))
                    .textSelection(.enabled)

                ForEach(Array(model.currentLesson.options.enumerated()), id: \.offset) { index, option in
                    lessonOptionRow(
                        title: option,
                        index: index,
                        isSelected: model.lessonSelectedOptionIndex == index
                    )
                }
            }

            HStack(spacing: 10) {
                Button("提交答案") {
                    model.submitLessonAnswer()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.44, green: 0.70, blue: 0.91))

                Text(model.lessonFeedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer()
            }

            Text("提示：这里的句子都可以鼠标选中，复制后可直接触发翻译。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已学习题目")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(model.selectedTopicLearningRecords.count) 题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.selectedTopicLearningRecords.isEmpty {
                    Text("你还没有提交过这个主题的题目。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.selectedTopicLearningRecords.prefix(8))) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text(record.lessonTitle)
                                    .font(.caption.weight(.semibold))
                                learningResultTag(title: record.isCorrect ? "正确" : "错误", isCorrect: record.isCorrect)
                                if !record.isCorrect {
                                    learningResultTag(title: "可回刷", isCorrect: false)
                                }
                                Spacer(minLength: 0)
                                Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Text(record.question)
                                .font(.caption)
                                .foregroundStyle(.primary)

                            Text("你的答案：\(record.selectedOption)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if !record.isCorrect {
                                Text("正确答案：\(record.correctOption)")
                                    .font(.caption2)
                                    .foregroundStyle(Color(red: 0.77, green: 0.33, blue: 0.21))
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private func learningResultTag(title: String, isCorrect: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCorrect ? Color(red: 0.15, green: 0.47, blue: 0.28) : Color(red: 0.75, green: 0.36, blue: 0.18))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isCorrect
                            ? Color(red: 0.88, green: 0.97, blue: 0.90)
                            : Color(red: 1.0, green: 0.92, blue: 0.86)
                    )
            )
    }

    private func lessonOptionRow(title: String, index: Int, isSelected: Bool) -> some View {
        Button {
            model.chooseLessonOption(index)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(
                        isSelected
                            ? Color(red: 0.25, green: 0.54, blue: 0.76)
                            : Color.secondary
                    )
                Text(title)
                    .foregroundStyle(.primary)
                    .font(.callout)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 0.87, green: 0.94, blue: 0.99)
                            : Color.white.opacity(0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("翻译结果")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))

                if model.isTranslating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if let result = model.latestResult {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(result.originalText)
                            .font(.title2.weight(.medium))
                        Text(result.direction.displayLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(Color.accentColor)
                        Button {
                            model.speak(result.originalText)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
                        }
                        .buttonStyle(.borderless)
                        .help("朗读原文")
                    }

                    Text(result.translatedText)
                        .font(.title3)

                    if let phonetic = result.phonetic,
                       !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if !result.explanations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(result.explanations, id: \.self) { explanation in
                                Text("• \(explanation)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("来源：\(result.provider)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("暂无翻译结果")
                        .font(.headline)
                    Text("在其他应用连续复制两次（⌘C, ⌘C），或手动输入翻译")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private func deleteFromFiltered(_ offsets: IndexSet) {
        let visibleItems = model.filteredHistory
        let ids: [Int64] = offsets.compactMap { (index: Int) -> Int64? in
            guard visibleItems.indices.contains(index) else { return nil }
            return visibleItems[index].id
        }

        requestDeleteHistory(ids: ids)
    }

    @ViewBuilder
    private func historyRowView(for item: LookupHistoryItem) -> some View {
        HistoryRow(
            item: item,
            isSelected: item.id == selectedHistoryID,
            isHovered: item.id == hoveredHistoryID,
            onDelete: {
                requestDeleteHistory(ids: [item.id])
            },
            onHover: { hovering in
                if hovering {
                    hoveredHistoryID = item.id
                } else if hoveredHistoryID == item.id {
                    hoveredHistoryID = nil
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedHistoryID = item.id
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("查看") {
                selectedHistoryID = item.id
                model.showHistoryItem(item)
            }
            Divider()
            Button("删除", role: .destructive) {
                requestDeleteHistory(ids: [item.id])
            }
        }
    }
}

private struct HistoryRow: View {
    let item: LookupHistoryItem
    let isSelected: Bool
    let isHovered: Bool
    let onDelete: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.rawText)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let source = item.sourceApp {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(item.createdAt.relativeDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout.weight(.semibold))
                    .padding(8)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.63, green: 0.78, blue: 0.95), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("删除")
            .padding(.trailing, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 0.88, green: 0.95, blue: 1.0)
                        : Color.white.opacity(0.70)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color(red: 0.72, green: 0.86, blue: 0.98) : Color.clear, lineWidth: 1)
                )
        )
        .onHover(perform: onHover)
    }
}

/// Compact window content for the menu bar extra — lets the user quickly type
/// a phrase and translate it without opening the main window.
struct MenubarPopoverView: View {
    @ObservedObject var model: AppModel
    @State private var draftText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("快速翻译")
                    .font(.headline)
                Spacer()
                if model.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextEditor(text: $draftText)
                .font(.callout)
                .frame(height: 80)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .focused($isInputFocused)
                .onAppear { isInputFocused = true }

            HStack {
                Text("⌘⏎ 翻译")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("翻译") {
                    performTranslate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draftText.trimmed.isEmpty || model.isTranslating)
            }

            if let result = model.latestResult {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(result.originalText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(result.direction.displayLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(result.translatedText)
                        .font(.callout.weight(.semibold))
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                    if let phonetic = result.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Button("立即翻译（读当前剪贴板）") {
                    model.translateSelectionNow()
                }
                .buttonStyle(.link)
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("打开主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.title == "English Coach" })?.makeKeyAndOrderFront(nil)
                }
                .buttonStyle(.link)

                Button("退出") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func performTranslate() {
        let text = draftText
        draftText = ""
        Task {
            await model.translateManualText(text)
        }
    }
}
