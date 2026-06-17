import AppKit
import SwiftUI

private enum DetailTab: String, CaseIterable, Identifiable {
    case translate
    case stats
    case words
    case route
    case interest
    case todos

    var id: String { rawValue }

    var label: String {
        switch self {
        case .translate: return "翻译"
        case .stats: return "统计"
        case .words: return "单词"
        case .route: return "路线"
        case .interest: return "兴趣"
        case .todos: return "待办"
        }
    }

    var systemImage: String {
        switch self {
        case .translate: return "character.book.closed"
        case .stats: return "chart.bar.xaxis"
        case .words: return "text.book.closed"
        case .route: return "map"
        case .interest: return "lightbulb"
        case .todos: return "checklist"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    @State private var selectedTab: DetailTab = .translate
    @State private var selectedHistoryID: Int64?
    @State private var hoveredHistoryID: Int64?
    @State private var isShowingMasteredWordsSheet: Bool = false
    @State private var masteredWordsScope: MasteredWordListScope = .all
    @State private var masteredWordSearchText: String = ""
    @State private var dailyWordRevealState = DailyWordTranslationRevealState()
    @State private var meetingPhraseRevealState = DailyWordTranslationRevealState()
    @State private var didPerformInitialActivation: Bool = false
    @State private var pendingHistoryDeletion: [Int64] = []
    @State private var isShowingHistoryDeleteConfirm: Bool = false
    @State private var didConfigureFrameAutosave: Bool = false
    @State private var isShowingShortcutHelp: Bool = false

    // Display sizes that keep their design value but follow the system text-size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var dailyWordFontSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title) private var meetingPhraseFontSize: CGFloat = 22
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
            LinearGradient.appWindow
            .ignoresSafeArea()
        )
        .onChange(of: model.shouldFocusTodoTab) { _, shouldFocus in
            if shouldFocus {
                selectedTab = .todos
                model.shouldFocusTodoTab = false
            }
        }
        .onAppear {
            if !didPerformInitialActivation {
                didPerformInitialActivation = true
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            if !didConfigureFrameAutosave,
               let window = NSApp.windows.first(where: { $0.title == "Nova" }) {
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

    private func openMasteredWords(scope: MasteredWordListScope) {
        masteredWordsScope = scope
        masteredWordSearchText = ""
        isShowingMasteredWordsSheet = true
        model.loadMasteredWordDefinitionsIfNeeded()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("学习记录")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColor.title)
                Spacer()
                Button {
                    Task {
                        await model.refreshHistory()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                        .padding(8)
                        .background(Color.glass(0.72), in: Circle())
                }
                .buttonStyle(.plain)
                .help("刷新")
                .accessibilityLabel("刷新")
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
                .fill(Color.glass(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.glass(0.75), lineWidth: 1)
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
                        todoStatsCard
                        activityHeatmapCard
                    case .words:
                        wordLearningCard
                    case .route:
                        learningRouteCard
                        meetingPhraseCard
                        productionDrillCard
                    case .interest:
                        interestLearningCard
                    case .todos:
                        TodoRootView(model: model)
                    }
                }
                .padding(24)
            }
        }
    }

    private var detailTabBar: some View {
        HStack(spacing: 2) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.label, systemImage: tab.systemImage)
                        .font(.callout.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(
                            selectedTab == tab
                                ? AppColor.title
                                : .secondary
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? Color.glass(0.72) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .hoverAffordance(cornerRadius: 8)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
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
                            .fill(Color.glass(0.45))
                    )
            }
            .buttonStyle(.plain)
            .help("设置")
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Color.glass(0.25))
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(AppColor.subtitle)
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !model.hasAccessibilityPermission {
                Image(systemName: "lock.shield")
                    .foregroundStyle(AppColor.warning)
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
                .tint(AppColor.warning)
                .help("重试上一次失败的翻译")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.glass(0.55))
        )
    }

    private var statsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("统计总览", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Text("今日")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], alignment: .leading, spacing: 10) {
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
                statChip(
                    title: "今日单词",
                    value: "\(model.todayWordDeckCount)",
                    systemImage: "rectangle.3.group.bubble"
                )
                Button {
                    openMasteredWords(scope: .today)
                } label: {
                    statChip(
                        title: "今日熟悉",
                        value: "\(model.todayMasteredWordCount)",
                        systemImage: "checkmark.circle"
                    )
                }
                .buttonStyle(.plain)
                Button {
                    openMasteredWords(scope: .all)
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
                    .foregroundStyle(AppColor.title)

                if model.todayTranslationItems.isEmpty {
                    Text("今天还没有翻译内容，选中句子后连续复制两次即可记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.todayTranslationItems.prefix(4))) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "dot.circle")
                                .font(.caption2)
                                .foregroundStyle(AppColor.accent)
                            Text(item.rawText)
                                .font(.caption)
                                .lineLimit(1)
                                .help(item.rawText)
                            Text("→")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.translation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(item.translation)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var todoStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("待办统计", systemImage: "checklist")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Text("\(model.openTodoCount) 项待完成")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            TodoStatsView(model: model)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var activityHeatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("活跃度日历", systemImage: "square.grid.3x3")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
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
        .cardSurface()
    }

    private var wordLearningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("每日单词学习", systemImage: "text.book.closed")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Text(model.dailyWordProgressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.hasCompletedDailyWordTarget {
                VStack(alignment: .leading, spacing: 8) {
                    Label("今日已完成", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppColor.successDeep)
                    Text(DailyWordProgress.completionMessage(
                        quota: model.todayDailyWordTarget,
                        groupSize: model.dailyWordGroupSize
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(Self.timeUntilNextDailyBatchDescription())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.subtitle)

                    HStack(spacing: 10) {
                        Button {
                            model.startNextDailyWordGroup()
                        } label: {
                            Label("学习下一组", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("查看累计熟悉") {
                            openMasteredWords(scope: .all)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .insetSurface(cornerRadius: 12)
            } else if let card = model.currentDailyWordCard {
                let isRevealed = dailyWordRevealState.isRevealed(for: card.id)

                VStack(alignment: .leading, spacing: 8) {
                    if card.isReview {
                        Label("复习", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppColor.tintOrange)
                            )
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(card.word)
                            .font(.system(size: dailyWordFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.ink)
                        Button {
                            model.speak(card.word)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundStyle(AppColor.subtitle)
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("p", modifiers: .command)
                        .help("朗读单词（⌘P）")
                        .accessibilityLabel("朗读单词")
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
                        .foregroundStyle(AppColor.subtitle)
                        .lineLimit(3)
                    Text("词义来源：\(card.provider)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .insetSurface(cornerRadius: 12)

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
                        .tint(AppColor.successDeep)
                        .keyboardShortcut("r", modifiers: [])
                        .help("还记得（R）")

                        Button {
                            model.forgotCurrentWord()
                        } label: {
                            Label("忘了", systemImage: "arrow.counterclockwise.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColor.warning)
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
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("上一个单词（←）")
                    .accessibilityLabel("上一个单词")

                    Button {
                        model.showNextDailyWord()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("下一个单词（→）")
                    .accessibilityLabel("下一个单词")

                    Spacer(minLength: 0)

                    Button("查看累计熟悉") {
                        openMasteredWords(scope: .all)
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
                        .foregroundStyle(AppColor.subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .insetSurface(cornerRadius: 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - 学习路线（关卡进阶）

    /// Roadmap overview: frames the chunk drill below as stage 1 of a path that
    /// builds toward real conversation, so memorising chunks feels like progress
    /// rather than another word list.
    private var learningRouteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("学习路线", systemImage: "map")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Text("目标：开会能跟上、能开口")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("背单词解决「看得懂」，但交流靠「说得出」。这条路线按能力进阶，先把开会要用的句子练到脱口而出。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                routeStageRow(
                    stage: 1,
                    title: "会议句块速记",
                    detail: "把高频口语句块用 SRS 记牢（下方）",
                    isActive: true,
                    isDone: false
                )
                routeStageRow(
                    stage: 2,
                    title: "句块跟读",
                    detail: "跟着发音影子跟读，练听力与语感",
                    isActive: false,
                    isDone: false
                )
                routeStageRow(
                    stage: 3,
                    title: "中译英产出",
                    detail: "看中文说英文，AI 批改更地道说法（下方）",
                    isActive: true,
                    isDone: false
                )
                routeStageRow(
                    stage: 4,
                    title: "会议角色扮演",
                    detail: "AI 扮演同事，完成一段来回对话",
                    isActive: false,
                    isDone: false
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func routeStageRow(stage: Int, title: String, detail: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isActive || isDone
                          ? AppColor.title
                          : Color.glass(0.9))
                    .frame(width: 26, height: 26)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColor.onAccent)
                } else {
                    Text("\(stage)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isActive ? AppColor.onAccent : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("关卡 \(stage) · \(title)")
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isActive {
                Text("可练习")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.subtitle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColor.tintBlue)
                    )
            } else {
                Text("待解锁")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.glass(0.85) : Color.glass(0.5))
        )
    }

    /// Stage 1 of the route: a production-first flashcard. The front shows only
    /// the Chinese situation, so the user tries to *produce* the English chunk
    /// out loud before revealing it — training recall, not recognition.
    private var meetingPhraseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("关卡 1 · 会议口语句块", systemImage: "questionmark.bubble")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Text(model.meetingPhraseProgressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("已掌握 \(model.meetingPhraseTotalMasteredCount)/\(model.meetingPhraseBankTotal) 句 · 先看中文场景，想好英文怎么说，再揭晓对照")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let card = model.currentMeetingPhraseCard {
                let isRevealed = meetingPhraseRevealState.isRevealed(for: card.id)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Label(card.category.title, systemImage: card.category.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.subtitle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppColor.tintBlue)
                            )

                        if card.isReview {
                            Label("复习", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppColor.tintOrange)
                                )
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("场景")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(card.scenario)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isRevealed {
                        Divider().opacity(0.4)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(card.english)
                                .font(.system(size: meetingPhraseFontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppColor.successDeep)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                model.speak(card.english)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppColor.subtitle)
                            }
                            .buttonStyle(.borderless)
                            .keyboardShortcut("p", modifiers: .command)
                            .help("朗读句块（⌘P）")
                            .accessibilityLabel("朗读句块")
                        }
                        Text(card.chinese)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("例句：\(card.example)")
                            .font(.caption)
                            .foregroundStyle(AppColor.subtitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        Text("先在心里把这句英文说出来 —— 按空格揭晓答案")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .insetSurface(cornerRadius: 12)

                HStack(spacing: 10) {
                    Button {
                        meetingPhraseRevealState.toggle(for: card.id)
                    } label: {
                        Label(
                            isRevealed ? "再次隐藏" : "揭晓答案",
                            systemImage: isRevealed ? "eye.slash" : "eye"
                        )
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(isRevealed ? "再次隐藏（空格）" : "揭晓英文（空格）")

                    if card.isReview {
                        Button {
                            model.rememberCurrentMeetingPhrase()
                        } label: {
                            Label("还记得", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColor.successDeep)
                        .keyboardShortcut("r", modifiers: [])
                        .help("还记得（R）")

                        Button {
                            model.forgotCurrentMeetingPhrase()
                        } label: {
                            Label("忘了", systemImage: "arrow.counterclockwise.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColor.warning)
                        .keyboardShortcut("f", modifiers: [])
                        .help("忘了（F）")
                    } else {
                        Button {
                            model.markCurrentMeetingPhraseMastered()
                        } label: {
                            Label(card.isMastered ? "已掌握" : "标记掌握", systemImage: card.isMastered ? "checkmark.circle.fill" : "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(card.isMastered)
                        .keyboardShortcut("d", modifiers: .command)
                        .help("标记为已掌握（⌘D），明天起进入复习计划")
                    }

                    Button {
                        model.showPreviousMeetingPhrase()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("上一个句块（←）")
                    .accessibilityLabel("上一个句块")

                    Button {
                        model.showNextMeetingPhrase()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("下一个句块（→）")
                    .accessibilityLabel("下一个句块")

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天的会议句块已经全部掌握 👍")
                        .font(.callout.weight(.semibold))
                    Text("明天会安排复习，或解锁新的一批句块。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .insetSurface(cornerRadius: 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Stage 3 of the route: Chinese→English production with AI grading. This
    /// trains output (the weak muscle) — the user writes English from a Chinese
    /// prompt and a Claude engine grades it with a polished version + notes.
    private var productionDrillCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("关卡 3 · 中译英产出", systemImage: "pencil.and.scribble")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Text("今日已练 \(model.drillsGradedToday) 句")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("看中文，自己写出英文，再让 AI 教练批改——练的是「能不能调出来、说得地道」。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.canGradeProduction {
                Label("此关卡需要 AI 引擎。请在设置（⌘,）中选择「本地 Claude CLI」或填入 Claude API Key。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AppColor.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppColor.tintOrange)
                    )
            }

            if let drill = model.currentDrill {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Label(drill.category.title, systemImage: drill.category.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.subtitle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(AppColor.tintBlue)
                            )
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("把这句话用英文说出来")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(drill.chinese)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let hint = drill.hint {
                            Text("提示：\(hint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextEditor(text: $model.drillInput)
                        .font(.callout)
                        .frame(height: 70)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .disabled(model.isGradingDrill)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .insetSurface(cornerRadius: 12)

                HStack(spacing: 10) {
                    Button {
                        Task { await model.gradeCurrentDrill() }
                    } label: {
                        if model.isGradingDrill {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("批改中…")
                            }
                        } else {
                            Label("提交批改", systemImage: "checkmark.bubble")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.successDeep)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isGradingDrill
                              || model.drillInput.trimmed.isEmpty
                              || !model.canGradeProduction)
                    .help("提交批改（⌘⏎）")

                    Button {
                        model.nextDrill()
                    } label: {
                        Label("换一句", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isGradingDrill)
                    .help("跳到下一句")

                    Spacer(minLength: 0)
                }

                if let error = model.drillGradeError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AppColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let grade = model.drillGrade {
                    gradeResultView(grade: grade, reference: drill.reference)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func gradeResultView(grade: ProductionGrade, reference: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verdictTitle(grade.verdict))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous).fill(verdictColor(grade.verdict))
                    )
                Text("AI 批改")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(grade.provider)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("更地道的说法")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(grade.polished)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppColor.successDeep)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button {
                        model.speak(grade.polished)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(AppColor.subtitle)
                    }
                    .buttonStyle(.borderless)
                    .help("朗读")
                    .accessibilityLabel("朗读")
                }
            }

            if !grade.notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(grade.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let encouragement = grade.encouragement {
                Text(encouragement)
                    .font(.caption)
                    .foregroundStyle(AppColor.subtitle)
            }

            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text("参考答案")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColor.tintGreen)
        )
    }

    private func verdictTitle(_ verdict: ProductionVerdict) -> String {
        switch verdict {
        case .great: return "很地道"
        case .good: return "基本可用"
        case .needsWork: return "可以更好"
        }
    }

    private func verdictColor(_ verdict: ProductionVerdict) -> Color {
        switch verdict {
        case .great: return AppColor.successDeep
        case .good: return AppColor.accent
        case .needsWork: return AppColor.warning
        }
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
                .foregroundStyle(AppColor.subtitle)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .insetSurface(cornerRadius: 10)
    }

    /// A flame-colored chip that stands out from the neutral stats — the
    /// streak is the one number worth looking at every day.
    private var streakChip: some View {
        let days = model.currentStreakDays
        return VStack(alignment: .leading, spacing: 5) {
            Label("连续", systemImage: "flame.fill")
                .font(.caption)
                .foregroundStyle(AppColor.warning)
            Text("\(days) 天")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(light: Color(red: 1.0, green: 0.93, blue: 0.82), dark: Color(red: 0.30, green: 0.22, blue: 0.10)),
                            Color(light: Color(red: 1.0, green: 0.88, blue: 0.70), dark: Color(red: 0.34, green: 0.24, blue: 0.10))
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
                Picker("", selection: $masteredWordsScope) {
                    ForEach(MasteredWordListScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                TextField("搜索已熟悉单词", text: $masteredWordSearchText)
                    .textFieldStyle(.roundedBorder)

                if masteredWordSections.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(masteredWordsEmptyTitle)
                            .font(.headline)
                        Text("在软件内“每日单词学习”里点击“标记熟悉”后会出现在这里。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    List {
                        ForEach(masteredWordSections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    masteredWordRow(item)
                                }
                            } header: {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(16)
            .navigationTitle(masteredWordsSheetTitle)
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
        .onAppear {
            model.loadMasteredWordDefinitionsIfNeeded()
        }
    }

    private var masteredWordsSheetTitle: String {
        switch masteredWordsScope {
        case .today: return "今日熟悉单词"
        case .all: return "累计熟悉单词"
        }
    }

    private var filteredMasteredWordItems: [MasteredWordListItem] {
        MasteredWordListPresentation.filteredItems(
            model.masteredWordItems,
            scope: masteredWordsScope,
            searchText: masteredWordSearchText
        )
    }

    private var masteredWordSections: [MasteredWordListSection] {
        MasteredWordListPresentation.sections(for: filteredMasteredWordItems)
    }

    private var masteredWordsEmptyTitle: String {
        MasteredWordListPresentation.emptyTitle(
            scope: masteredWordsScope,
            hasAnyItems: !model.masteredWordItems.isEmpty,
            isSearching: !masteredWordSearchText.trimmed.isEmpty
        )
    }

    private func masteredWordRow(_ item: MasteredWordListItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.word)
                        .font(.body.monospaced().weight(.semibold))
                    if let phonetic = item.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.caption.monospaced())
                            .foregroundStyle(AppColor.purple)
                    }
                }

                Text(masteredWordTranslationText(for: item))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(item.translation == nil ? .secondary : .primary)
                    .lineLimit(2)

                if let definition = item.definition, !definition.isEmpty {
                    Text(definition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Label(
                        MasteredWordListPresentation.masteredTimeText(for: item.masteredAt),
                        systemImage: "calendar"
                    )
                    Label(
                        MasteredWordListPresentation.reviewText(for: item),
                        systemImage: item.isGraduated ? "checkmark.seal" : "clock.arrow.circlepath"
                    )
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Button("取消熟悉") {
                model.unmarkMasteredWord(item.word)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func masteredWordTranslationText(for item: MasteredWordListItem) -> String {
        guard let translation = item.translation, !translation.isEmpty else {
            return "暂无本地释义"
        }
        return translation
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
                    .foregroundStyle(AppColor.title)
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
                .tint(AppColor.accent)
                .disabled(model.manualInput.trimmed.isEmpty || model.isTranslating)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var interestLearningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("兴趣学习")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.title)
                Spacer()
                Label("今日 \(model.todayLearningAttemptCount)", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.subtitle)
                if model.currentLessonIsReview {
                    Label("错题回刷", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.warning)
                }
                Label("累计 \(model.completedLearningCards)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.subtitle)
                Label("连胜 \(model.learningStreakDays) 天", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.warning)
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
                    .foregroundStyle(AppColor.successDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppColor.tintGreen)
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
                .insetSurface(cornerRadius: 10)
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
                .tint(AppColor.accent)

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
                                    .foregroundStyle(AppColor.danger)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .insetSurface(cornerRadius: 10)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func learningResultTag(title: String, isCorrect: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCorrect ? AppColor.successDeep : AppColor.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isCorrect
                            ? AppColor.tintGreen
                            : AppColor.tintOrange
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
                            ? AppColor.accent
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
                            ? AppColor.tintBlue
                            : Color.glass(0.7)
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverAffordance(cornerRadius: 10)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("翻译结果")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.title)

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
                                .foregroundStyle(AppColor.subtitle)
                        }
                        .buttonStyle(.borderless)
                        .help("朗读原文")
                        .accessibilityLabel("朗读原文")

                        Spacer()

                        if model.canAddLookupToLearning(result) {
                            Button {
                                model.addLookupToLearning(result)
                            } label: {
                                Label("加入生词本", systemImage: "text.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(AppColor.successDeep)
                            .help("把这个单词加入每日学习与复习")
                        }
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

                    if let context = model.latestLookupContext,
                       !context.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("原句", systemImage: "quote.opening")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Text(context)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.06))
                        )
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
        .cardSurface()
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { selectedHistoryID = item.id }
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
                    .help(item.rawText)

                Text(item.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(item.translation)

                if let context = item.context, !context.isEmpty {
                    Text("“\(context)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(2)
                }

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

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.callout.weight(.semibold))
                    .padding(8)
                    .foregroundStyle(.white)
                    .background(AppColor.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("删除")
            .accessibilityLabel("删除")
            .padding(.trailing, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AppColor.accent : Color.clear, lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover(perform: onHover)
        .pointerOnHover()
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return AppColor.tintBlue
        }
        if isHovered {
            return AppColor.tintBlue
        }
        return Color.glass(0.70)
    }
}

/// Pointer cursor + a subtle accent border on hover, for custom tappable areas
/// (tabs, answer rows) that don't get the system button's hover treatment.
private struct HoverAffordance: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(hovering ? 0.45 : 0), lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { isHovering in
                hovering = isHovering
                if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }
}

/// Just the pointing-hand cursor on hover, for rows that already have their own
/// visible hover state (e.g. history rows revealing a delete button).
private struct PointerOnHover: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private extension View {
    func hoverAffordance(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverAffordance(cornerRadius: cornerRadius))
    }

    func pointerOnHover() -> some View {
        modifier(PointerOnHover())
    }
}
