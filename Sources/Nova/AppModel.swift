import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let dailyWordQuota = 20

    @Published var statusMessage: String = "在任意应用中连续按两次复制（⌘C, ⌘C）即可翻译"
    @Published var latestResult: TranslationResult?
    /// Sentence the latest lookup came from, when captured from the source app.
    @Published var latestLookupContext: String?
    @Published var history: [LookupHistoryItem] = []
    @Published var searchText: String = ""
    @Published var manualInput: String = ""
    @Published var isTranslating: Bool = false
    @Published var hasAccessibilityPermission: Bool = false
    @Published var hotkeyStatus: HotkeyStatus = .registered

    @Published var selectedTopic: InterestTopic = .movies
    @Published var currentLesson: InterestLesson = AppModel.makeLesson(topic: .movies, seed: 0)
    @Published var currentLessonIsReview: Bool = false
    @Published var isCurrentTopicExhausted: Bool = false
    @Published var lessonSelectedOptionIndex: Int?
    @Published var lessonFeedbackMessage: String = "选择你感兴趣的主题，开始今天的兴趣学习。"
    @Published var completedLearningCards: Int = 0
    @Published var learningStreakDays: Int = 0
    @Published var hasCompletedLearningToday: Bool = false
    @Published var learningAttempts: [LearningAttemptRecord] = []

    @Published var dailyWordCards: [DesktopWordCard] = []
    @Published var currentDailyWordIndex: Int = 0
    @Published var todayWordDeckCount: Int = 0
    @Published var todayMasteredWordCount: Int = 0
    @Published var todayDailyWordTarget: Int = AppModel.dailyWordQuota
    @Published var totalMasteredWordCount: Int = 0
    @Published var allMasteredWords: [String] = []
    @Published var masteredWordItems: [MasteredWordListItem] = []
    @Published var todayReviewCount: Int = 0

    // MARK: - 会议口语句块（学习路线 · 关卡1）
    @Published var meetingPhraseCards: [MeetingPhraseCard] = []
    @Published var currentMeetingPhraseIndex: Int = 0
    @Published var meetingPhraseTodayCount: Int = 0
    @Published var meetingPhraseTodayMasteredCount: Int = 0
    @Published var meetingPhraseTotalMasteredCount: Int = 0
    @Published var meetingPhraseReviewCount: Int = 0

    // MARK: - 中译英产出 + AI 批改（学习路线 · 关卡3）
    @Published var currentDrill: ProductionDrill?
    @Published var drillInput: String = ""
    @Published var isGradingDrill: Bool = false
    @Published var drillGrade: ProductionGrade?
    @Published var drillGradeError: String?
    @Published var drillsGradedToday: Int = 0

    // MARK: - 待办清单
    @Published var todos: [TodoItem] = []
    @Published var customTags: [String] = []
    @Published var templates: [TodoTemplate] = []
    @Published var savedReports: [String: String] = [:]
    @Published var todoMemo: String = ""
    @Published var todoMemoUpdatedAt: Date?
    /// Filter / search / sort UI state (not persisted, mirrors the web app).
    @Published var todoFilterCategory: TodoCategory?
    @Published var todoFilterStatus: TodoStatus?
    @Published var todoSearchQuery: String = ""
    @Published var todoFilterTag: String = ""
    @Published var todoSortByPriority: Bool = false
    /// Most recently deleted todo, surfaced as an undo affordance.
    @Published var deletedTodo: TodoItem?
    /// Weekly-report week offset (0 = current week, -1 = last week).
    @Published var weeklyReportOffset: Int = 0
    /// Set when the desktop pet wants the main window opened on the 待办 tab;
    /// ContentView observes this and switches tabs, then resets it.
    @Published var shouldFocusTodoTab: Bool = false

    @Published var translationPresentationMode: TranslationPresentation = .floating {
        didSet {
            guard oldValue != translationPresentationMode else { return }
            defaults.set(translationPresentationMode.rawValue, forKey: Self.translationPresentationModeKey)
            syncDesktopPetVisibility()
        }
    }
    @Published var translationEngine: TranslationEngine = .localCLI {
        didSet {
            guard oldValue != translationEngine else { return }
            defaults.set(translationEngine.rawValue, forKey: Self.translationEngineKey)
            pushClaudeConfiguration()
        }
    }
    @Published var claudeAPIKey: String = "" {
        didSet {
            guard oldValue != claudeAPIKey else { return }
            defaults.set(claudeAPIKey, forKey: Self.claudeAPIKeyKey)
            pushClaudeConfiguration()
        }
    }
    @Published var claudeModel: String = ClaudeTranslationProvider.defaultModel {
        didSet {
            guard oldValue != claudeModel else { return }
            defaults.set(claudeModel, forKey: Self.claudeModelKey)
            pushClaudeConfiguration()
        }
    }
    @Published var manualDirectionChoice: TranslationDirectionChoice = .auto
    @Published var historyTimeFilter: HistoryTimeFilter = .all
    @Published var reminderEnabled: Bool = false
    @Published var reminderTime: Date = AppModel.defaultReminderTime()
    /// True when the most recent translation request didn't produce a real
    /// answer (online unavailable + no local dictionary entry, or the call
    /// threw). The status card surfaces a "重试" button while this is true.
    @Published private(set) var pendingRetry: Bool = false

    private let hotkeyManager: GlobalHotkeyManager
    private let selectedTextService: SelectedTextService
    private let translationService: TranslationService
    private let historyStore: HistoryStore?
    /// SQLite-backed todo list (ported from the standalone TodoList app). `nil`
    /// if the store failed to open — the UI degrades gracefully.
    private let todoStore: TodoStore?
    /// Pending hard-delete of a todo, cancelable within the undo window.
    private var todoUndoWorkItem: DispatchWorkItem?
    /// Debounced memo autosave.
    private var todoMemoSaveWork: DispatchWorkItem?
    private let defaults: UserDefaults
    private let wordCarouselStore: WordCarouselStore
    private let masteredWordDictionary = ECDICTDictionary()
    /// Reuses the same SRS engine as the word deck, keyed independently, to
    /// schedule meeting-phrase chunks.
    private let meetingPhraseStore: WordCarouselStore
    private let calendar = Calendar.current
    private let popoverController = TranslationPopoverController()
    private let reminderScheduler = ReminderScheduler()
    private let speechService = SpeechService()
    private let servicesProvider = ServicesProvider()

    private var lessonSeedOffset: Int = 0
    /// Index into `ProductionDrillBank.all` for the current drill; persisted so
    /// drills continue where the user left off across launches.
    private var drillIndex: Int = 0
    /// Timestamps of graded production attempts — feeds the activity heatmap and
    /// the "今日已练 N 句" counter.
    private var productionDrillDates: [Date] = []
    private var lastCompletedLearningDate: Date?
    private var lessonProgressStates: [String: LessonProgressState] = [:]
    private var wordDefinitionCache: [String: TranslationResult] = [:]
    private var loadingWordDefinitions: Set<String> = []
    private var lastFailedRequest: PendingRetryRequest?
    /// The most recent translation that was shown in the floating pet bubble,
    /// so right-clicking the pet can re-surface it.
    private var lastFloatingResult: (result: TranslationResult, sourceApp: String?)?

    /// Captured payload of the most recent failing translation, kept so the
    /// "重试" button can replay the exact same call (text + source + where to
    /// surface the result).
    private struct PendingRetryRequest {
        let text: String
        let sourceApp: String?
        let context: String?
        let presentation: PresentationTarget
        let direction: TranslationDirection?
    }

    private static let completedCardsKey = "learning.completedCards"
    private static let learningStreakDaysKey = "learning.streakDays"
    private static let lastCompletedDateKey = "learning.lastCompletedDate"
    private static let learningAttemptsKey = "learning.attempts.v1"
    private static let lessonProgressStatesKey = "learning.lessonProgressStates.v1"
    private static let drillIndexKey = "productionDrill.index.v1"
    private static let drillDatesKey = "productionDrill.dates.v1"
    private static let translationPresentationModeKey = "translation.presentationMode"
    private static let translationEngineKey = "translation.engine"
    private static let claudeAPIKeyKey = "translation.claudeAPIKey"
    private static let claudeModelKey = "translation.claudeModel"
    private static let reminderEnabledKey = "reminder.enabled"
    private static let reminderHourKey = "reminder.hour"
    private static let reminderMinuteKey = "reminder.minute"

    private struct LessonProgressState: Codable {
        var topicRawValue: String
        var lessonTitle: String
        var question: String
        var hasWrongAttempt: Bool
        var isMastered: Bool
        var attempts: Int
        var lastAttemptAt: Date
    }

    init(
        hotkeyManager: GlobalHotkeyManager = GlobalHotkeyManager(),
        selectedTextService: SelectedTextService = SelectedTextService(),
        translationService: TranslationService = TranslationService(enableOnlineFallback: true),
        defaults: UserDefaults = .standard
    ) {
        self.hotkeyManager = hotkeyManager
        self.selectedTextService = selectedTextService
        self.translationService = translationService
        self.defaults = defaults
        self.wordCarouselStore = WordCarouselStore(
            defaults: defaults,
            coreWords: CommonWordBank.coreWords,
            extendedWords: CommonWordBank.extendedWords,
            dailyQuota: Self.dailyWordQuota
        )
        self.meetingPhraseStore = WordCarouselStore(
            defaults: defaults,
            coreWords: MeetingPhraseBank.allIDs,
            extendedWords: [],
            dailyQuota: 6,
            stateKey: "meetingPhrase.state.v1"
        )

        hotkeyManager.setDoubleCopyInterval(0.8)

        do {
            historyStore = try HistoryStore()
        } catch {
            historyStore = nil
            statusMessage = "数据库初始化失败：\(error.localizedDescription)"
        }

        do {
            todoStore = try TodoStore()
        } catch {
            todoStore = nil
            statusMessage = "待办数据初始化失败：\(error.localizedDescription)"
        }

        hasAccessibilityPermission = selectedTextService.isAccessibilityTrusted()

        if let raw = defaults.string(forKey: Self.translationPresentationModeKey),
           let mode = TranslationPresentation(rawValue: raw) {
            self.translationPresentationMode = mode
        }

        if let raw = defaults.string(forKey: Self.translationEngineKey),
           let engine = TranslationEngine(rawValue: raw) {
            self.translationEngine = engine
        }
        self.claudeAPIKey = defaults.string(forKey: Self.claudeAPIKeyKey) ?? ""
        if let storedModel = defaults.string(forKey: Self.claudeModelKey), !storedModel.isEmpty {
            self.claudeModel = storedModel
        }
        // Property observers don't fire during init — push explicitly.
        pushClaudeConfiguration()

        self.reminderEnabled = defaults.bool(forKey: Self.reminderEnabledKey)
        if defaults.object(forKey: Self.reminderHourKey) != nil {
            let hour = defaults.integer(forKey: Self.reminderHourKey)
            let minute = defaults.integer(forKey: Self.reminderMinuteKey)
            self.reminderTime = Self.makeReminderTime(hour: hour, minute: minute)
        }

        self.popoverController.onOpenMainWindow = { [weak self] in
            self?.openMainWindow()
        }
        self.popoverController.onRequestQuickTranslate = { [weak self] in
            guard let self else { return }
            self.popoverController.presentQuickTranslate(model: self, near: self.bestPopoverPosition())
        }
        self.popoverController.onRequestClipboardTranslation = { [weak self] in
            self?.translateSelectionNow()
        }
        self.popoverController.onRequestDailyWord = { [weak self] in
            self?.showDesktopDailyWordInvite()
        }
        self.popoverController.onRequestLastTranslation = { [weak self] in
            self?.showLastTranslationBubble()
        }
        self.popoverController.onDailyWordComplete = { [weak self] card in
            self?.completeDesktopDailyWord(card)
        }
        self.popoverController.onDailyWordPractice = { [weak self] card in
            self?.practiceDesktopDailyWord(card)
        }
        self.popoverController.onStartNextDailyWordGroup = { [weak self] in
            self?.startNextDailyWordGroup()
            self?.showDesktopDailyWordInvite()
        }
        self.popoverController.onAddToLearning = { [weak self] result in
            self?.addLookupToLearningFromBubble(result)
        }
        self.popoverController.onRequestQuickAddTodo = { [weak self] in
            self?.popoverController.presentTodoFormBubble()
        }
        self.popoverController.onSubmitNewTodo = { [weak self] draft in
            self?.addTodoFromPet(draft)
        }
        self.popoverController.onRequestShowTodos = { [weak self] in
            self?.showDesktopTodos()
        }
        self.popoverController.onCompleteTodo = { [weak self] id in
            self?.completeTodoFromPet(id: id)
        }
        self.popoverController.onRequestOpenTodoList = { [weak self] in
            self?.openTodoListFromPet()
        }

        self.hotkeyManager.onHotKeyPressed = { [weak self] in
            guard let self else { return }
            Task {
                await self.handleHotkeyTriggeredTranslation()
            }
        }

        self.hotkeyManager.onQuickTranslatePressed = { [weak self] in
            guard let self else { return }
            let position = self.bestPopoverPosition()
            self.popoverController.presentQuickTranslate(model: self, near: position)
        }

        do {
            try hotkeyManager.registerDefaultShortcut()
            hotkeyStatus = .registered
        } catch {
            hotkeyStatus = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }

        // Register as the macOS Services provider so the system's Services menu
        // can call into us. `NSUpdateDynamicServices` nudges the system to
        // re-scan the Info.plist entries for this bundle so a fresh build
        // doesn't need a logout to show up in the Services menu.
        servicesProvider.appModel = self
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()

        loadLearningProgress()
        refreshLessonForSelectedTopic()
        refreshWordCarouselIfNeeded()
        refreshMeetingPhrasesIfNeeded()
        loadProductionDrillState()
        loadTodoState()

        Task {
            await refreshHistory()
        }

        if reminderEnabled {
            let components = calendar.dateComponents([.hour, .minute], from: reminderTime)
            let hour = components.hour ?? 20
            let minute = components.minute ?? 0
            reminderScheduler.schedule(hour: hour, minute: minute)
            if hasCompletedLearningToday {
                reminderScheduler.suppressForToday(hour: hour, minute: minute)
            }
        }
    }

    var filteredHistory: [LookupHistoryItem] {
        let timeFiltered: [LookupHistoryItem]
        switch historyTimeFilter {
        case .all:
            timeFiltered = history
        case .today:
            timeFiltered = history.filter { calendar.isDateInToday($0.createdAt) }
        case .thisWeek:
            let now = Date()
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
                timeFiltered = history
                break
            }
            timeFiltered = history.filter { $0.createdAt >= weekStart }
        }

        let query = searchText.normalizedForLookup
        guard !query.isEmpty else { return timeFiltered }
        return timeFiltered.filter { item in
            item.normalizedText.contains(query)
                || item.translation.lowercased().contains(query)
                || (item.sourceApp?.lowercased().contains(query) ?? false)
        }
    }

    var todayTranslationCount: Int {
        todayTranslationItems.count
    }

    var todayTranslationItems: [LookupHistoryItem] {
        history.filter { calendar.isDateInToday($0.createdAt) }
    }

    var todayLearningAttemptCount: Int {
        learningAttempts.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    var todayLearningCorrectCount: Int {
        learningAttempts.filter { attempt in
            attempt.isCorrect && calendar.isDateInToday(attempt.createdAt)
        }.count
    }

    var todayLearningWrongCount: Int {
        learningAttempts.filter { attempt in
            !attempt.isCorrect && calendar.isDateInToday(attempt.createdAt)
        }.count
    }

    var selectedTopicLearningRecords: [LearningAttemptRecord] {
        var latestByTemplate: [String: LearningAttemptRecord] = [:]
        for record in learningAttempts where record.topicRawValue == selectedTopic.rawValue {
            if let existing = latestByTemplate[record.lessonTemplateID] {
                if record.createdAt > existing.createdAt {
                    latestByTemplate[record.lessonTemplateID] = record
                }
            } else {
                latestByTemplate[record.lessonTemplateID] = record
            }
        }

        return latestByTemplate.values.sorted { $0.createdAt > $1.createdAt }
    }

    var currentDailyWordCard: DesktopWordCard? {
        guard !dailyWordCards.isEmpty else { return nil }
        if dailyWordCards.indices.contains(currentDailyWordIndex) {
            return dailyWordCards[currentDailyWordIndex]
        }
        return dailyWordCards.first
    }

    var dailyWordProgressText: String {
        let base = DailyWordProgress.statusText(
            masteredToday: todayMasteredWordCount,
            quota: todayDailyWordTarget,
            hasAvailableCard: currentDailyWordCard != nil
        )
        if todayReviewCount > 0 {
            return "\(base) · 复习 \(todayReviewCount)"
        }
        return base
    }

    var hasCompletedDailyWordTarget: Bool {
        todayMasteredWordCount >= todayDailyWordTarget
    }

    var dailyWordGroupSize: Int {
        Self.dailyWordQuota
    }

    var currentMeetingPhraseCard: MeetingPhraseCard? {
        guard !meetingPhraseCards.isEmpty else { return nil }
        if meetingPhraseCards.indices.contains(currentMeetingPhraseIndex) {
            return meetingPhraseCards[currentMeetingPhraseIndex]
        }
        return meetingPhraseCards.first
    }

    var meetingPhraseProgressText: String {
        guard !meetingPhraseCards.isEmpty else { return "今日句块已全部掌握" }
        let shownIndex = min(currentMeetingPhraseIndex, meetingPhraseCards.count - 1) + 1
        let base = "今日句块 \(shownIndex)/\(meetingPhraseCards.count)"
        if meetingPhraseReviewCount > 0 {
            return "\(base) · 复习 \(meetingPhraseReviewCount)"
        }
        return base
    }

    /// Total chunks in the bank, for the "路线进度" line.
    var meetingPhraseBankTotal: Int { MeetingPhraseBank.cards.count }

    /// Aggregate activity events per calendar day, keyed by `yyyy-MM-dd`.
    /// Combines translations, interest learning attempts, and newly mastered
    /// words into a single count so the heatmap can color one cell per day.
    var dailyActivityCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for item in history {
            counts[Self.dayKey(for: item.createdAt, calendar: calendar), default: 0] += 1
        }
        for attempt in learningAttempts {
            counts[Self.dayKey(for: attempt.createdAt, calendar: calendar), default: 0] += 1
        }
        for date in wordCarouselStore.masteryDates() {
            counts[Self.dayKey(for: date, calendar: calendar), default: 0] += 1
        }
        for date in meetingPhraseStore.masteryDates() {
            counts[Self.dayKey(for: date, calendar: calendar), default: 0] += 1
        }
        for date in productionDrillDates {
            counts[Self.dayKey(for: date, calendar: calendar), default: 0] += 1
        }
        for todo in todos {
            if let completedAt = todo.completedAt {
                counts[Self.dayKey(for: completedAt, calendar: calendar), default: 0] += 1
            }
        }
        return counts
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    /// Consecutive days of learning activity ending at today (or yesterday if
    /// today has no activity yet — we don't want to show "streak broken" at
    /// 8am just because the day just started).
    var currentStreakDays: Int {
        let counts = dailyActivityCounts
        let now = Date()
        let todayKey = Self.dayKey(for: now, calendar: calendar)

        // Anchor: today if today already has activity, otherwise yesterday —
        // so an unfinished today doesn't zero out the streak visually.
        var cursor: Date
        if (counts[todayKey] ?? 0) > 0 {
            cursor = calendar.startOfDay(for: now)
        } else {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
                return 0
            }
            cursor = calendar.startOfDay(for: yesterday)
        }

        var streak = 0
        while true {
            let key = Self.dayKey(for: cursor, calendar: calendar)
            guard (counts[key] ?? 0) > 0 else { break }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            // Hard cap to avoid any pathological data sending us into an
            // infinite loop; real streaks are never multi-year on a personal app.
            if streak >= 3650 { break }
        }
        return streak
    }

    /// How many actionable items the user still has today: review-due words
    /// that haven't been answered yet + new words that haven't been marked
    /// mastered yet. This drives the Dock badge.
    var pendingLearningTaskCount: Int {
        let unmasteredToday = max(0, todayDailyWordTarget - todayMasteredWordCount)
        let unmasteredPhrases = max(0, meetingPhraseTodayCount - meetingPhraseTodayMasteredCount)
        return todayReviewCount + unmasteredToday + meetingPhraseReviewCount + unmasteredPhrases
    }

    /// Apply `pendingLearningTaskCount` to the Dock tile. Empty string removes
    /// the badge so the icon looks clean when there's nothing to do.
    func refreshDockBadge() {
        let count = pendingLearningTaskCount
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    var wordBankScaleDescription: String {
        let core = CommonWordBank.coreWords.count
        let extended = CommonWordBank.extendedWords.count
        if CommonWordBank.wordSourceAvailable {
            return "词库规模：\(core + extended) 词（CET-4 核心 \(core) + CET-6 扩展 \(extended)）"
        } else {
            return "词库规模：0 词（词库来源 ecdict.db 不可用，请运行 scripts/fetch_ecdict.sh）"
        }
    }

    func refreshWordCarouselIfNeeded() {
        let snapshot = wordCarouselStore.snapshot()
        todayWordDeckCount = snapshot.todayWords.count
        todayMasteredWordCount = snapshot.todayMasteredCount
        todayDailyWordTarget = snapshot.dailyTarget
        totalMasteredWordCount = snapshot.totalMasteredCount
        allMasteredWords = snapshot.masteredWords.sorted()
        refreshMasteredWordItems(from: snapshot.masteredRecords)
        todayReviewCount = snapshot.reviewDueWords.count

        // Combine review-due words (front) with fresh today words. They can't
        // overlap by construction (review pool is mastered, today pool excludes
        // mastered), but dedup defensively to survive any storage drift.
        var seen: Set<String> = []
        var combined: [(word: String, isReview: Bool)] = []
        for word in snapshot.reviewDueWords where seen.insert(word).inserted {
            combined.append((word, true))
        }
        for word in snapshot.todayWords where seen.insert(word).inserted {
            combined.append((word, false))
        }

        let previousWord = currentDailyWordCard?.word
        dailyWordCards = combined.map { entry in
            var card = DesktopWordCard(
                word: entry.word,
                meaning: "正在加载词义...",
                phonetic: nil,
                explanation: "常用词，加载释义中",
                example: CommonWordBank.exampleSentence(for: entry.word),
                provider: "Word Bank",
                isMastered: snapshot.masteredWords.contains(entry.word),
                isReview: entry.isReview,
                progressBadgeText: DailyWordProgress.bubbleBadgeText(
                    masteredToday: snapshot.todayMasteredCount,
                    quota: snapshot.dailyTarget,
                    isReview: entry.isReview
                )
            )

            if let cached = wordDefinitionCache[entry.word] {
                Self.applyDefinition(cached, to: &card)
            }

            return card
        }

        if let previousWord,
           let index = dailyWordCards.firstIndex(where: { $0.word == previousWord }) {
            currentDailyWordIndex = index
        } else if dailyWordCards.isEmpty {
            currentDailyWordIndex = 0
        } else {
            currentDailyWordIndex = min(currentDailyWordIndex, dailyWordCards.count - 1)
        }

        for entry in combined {
            loadWordDefinitionIfNeeded(for: entry.word)
        }

        refreshDockBadge()
    }

    func showNextDailyWord() {
        guard !dailyWordCards.isEmpty else { return }
        currentDailyWordIndex = DailyWordDeckNavigation.nextIndex(
            after: currentDailyWordIndex,
            cardCount: dailyWordCards.count
        )
    }

    func showPreviousDailyWord() {
        guard !dailyWordCards.isEmpty else { return }
        currentDailyWordIndex = (currentDailyWordIndex - 1 + dailyWordCards.count) % dailyWordCards.count
    }

    func markCurrentWordAsMastered() {
        guard let card = currentDailyWordCard else { return }
        guard !card.isReview else { return }
        guard !card.isMastered else { return }

        wordCarouselStore.markMastered(word: card.word)
        refreshWordCarouselIfNeeded()
        statusMessage = "已标记熟悉：\(card.word)，明天会安排第一次复习"
    }

    func rememberCurrentWord() {
        guard let card = currentDailyWordCard else { return }
        guard card.isReview else { return }

        wordCarouselStore.advanceReview(word: card.word)
        refreshWordCarouselIfNeeded()

        if let days = wordCarouselStore.daysUntilNextReview(for: card.word) {
            statusMessage = days <= 0
                ? "继续保持：\(card.word)，今天稍后再复习一次"
                : "继续保持：\(card.word)，下次复习在 \(days) 天后"
        } else {
            statusMessage = "继续保持：\(card.word)，已毕业，不再安排复习"
        }
    }

    func forgotCurrentWord() {
        guard let card = currentDailyWordCard else { return }
        guard card.isReview else { return }

        wordCarouselStore.resetReview(word: card.word)
        refreshWordCarouselIfNeeded()
        statusMessage = "重置进度：\(card.word)，明天再复习一次"
    }

    func markCurrentWordNeedsPractice() {
        guard let card = currentDailyWordCard else { return }
        guard !card.isReview, !card.isMastered else { return }

        wordCarouselStore.markNeedsPractice(word: card.word)
        refreshWordCarouselIfNeeded()
        statusMessage = "已记录不熟悉：\(card.word)，后续会加强复习"
    }

    func unmarkMasteredWord(_ word: String) {
        wordCarouselStore.unmarkMastered(word: word)
        refreshWordCarouselIfNeeded()
        statusMessage = "已取消熟悉：\(word)，会重新进入后续学习"
    }

    func startNextDailyWordGroup() {
        wordCarouselStore.expandTodayTarget()
        refreshWordCarouselIfNeeded()
        let nextIndex = min(todayMasteredWordCount + 1, todayDailyWordTarget)
        statusMessage = "已开启下一组：今日单词 \(nextIndex)/\(todayDailyWordTarget)"
    }

    func loadMasteredWordDefinitionsIfNeeded() {
        let missingWords = masteredWordItems
            .filter { $0.translation == nil && $0.definition == nil }
            .map(\.word)
        guard !missingWords.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            for word in missingWords {
                guard self.wordDefinitionCache[word] == nil else { continue }
                if let entry = await self.masteredWordDictionary.lookup(word) {
                    let result = TranslationResult(
                        originalText: word,
                        translatedText: entry.translation,
                        phonetic: entry.phonetic,
                        explanations: entry.definition?
                            .split(separator: "\n")
                            .map { String($0).trimmed }
                            .filter { !$0.isEmpty } ?? [],
                        provider: "ECDICT 本地词典",
                        direction: .englishToChinese
                    )
                    self.wordDefinitionCache[word] = result
                }
            }
            self.refreshMasteredWordItems(from: self.wordCarouselStore.snapshot().masteredRecords)
        }
    }

    private func refreshMasteredWordItems(from records: [MasteredWordRecord]) {
        masteredWordItems = records.map { record in
            let definition = wordDefinitionCache[record.word]
            return MasteredWordListItem(
                word: record.word,
                masteredAt: record.masteredAt,
                phonetic: definition?.phonetic,
                translation: definition?.translatedText,
                definition: definition?.explanations.first,
                nextReviewDue: record.isGraduated ? nil : record.nextReviewDue,
                isGraduated: record.isGraduated
            )
        }
    }

    // MARK: - 会议口语句块动作

    func refreshMeetingPhrasesIfNeeded() {
        let snapshot = meetingPhraseStore.snapshot()
        meetingPhraseTodayCount = snapshot.todayWords.count
        meetingPhraseTodayMasteredCount = snapshot.todayMasteredCount
        meetingPhraseTotalMasteredCount = snapshot.totalMasteredCount
        meetingPhraseReviewCount = snapshot.reviewDueWords.count

        // Review-due chunks ride at the front, then today's fresh chunks.
        var seen: Set<String> = []
        var combined: [(id: String, isReview: Bool)] = []
        for id in snapshot.reviewDueWords where seen.insert(id).inserted {
            combined.append((id, true))
        }
        for id in snapshot.todayWords where seen.insert(id).inserted {
            combined.append((id, false))
        }

        let previousID = currentMeetingPhraseCard?.id
        // `compactMap` drops any persisted id no longer in the bank (e.g. after
        // the curated list changes), so stale state never crashes the deck.
        meetingPhraseCards = combined.compactMap { entry in
            guard var card = MeetingPhraseBank.card(forID: entry.id) else { return nil }
            card.isReview = entry.isReview
            card.isMastered = snapshot.masteredWords.contains(entry.id)
            return card
        }

        if let previousID,
           let index = meetingPhraseCards.firstIndex(where: { $0.id == previousID }) {
            currentMeetingPhraseIndex = index
        } else if meetingPhraseCards.isEmpty {
            currentMeetingPhraseIndex = 0
        } else {
            currentMeetingPhraseIndex = min(currentMeetingPhraseIndex, meetingPhraseCards.count - 1)
        }

        refreshDockBadge()
    }

    func showNextMeetingPhrase() {
        guard !meetingPhraseCards.isEmpty else { return }
        currentMeetingPhraseIndex = (currentMeetingPhraseIndex + 1) % meetingPhraseCards.count
    }

    func showPreviousMeetingPhrase() {
        guard !meetingPhraseCards.isEmpty else { return }
        currentMeetingPhraseIndex = (currentMeetingPhraseIndex - 1 + meetingPhraseCards.count) % meetingPhraseCards.count
    }

    func markCurrentMeetingPhraseMastered() {
        guard let card = currentMeetingPhraseCard else { return }
        guard !card.isReview, !card.isMastered else { return }

        meetingPhraseStore.markMastered(word: card.id)
        refreshMeetingPhrasesIfNeeded()
        statusMessage = "已掌握句块：\(card.english)，明天会安排第一次复习"
    }

    func rememberCurrentMeetingPhrase() {
        guard let card = currentMeetingPhraseCard else { return }
        guard card.isReview else { return }

        meetingPhraseStore.advanceReview(word: card.id)
        refreshMeetingPhrasesIfNeeded()

        if let days = meetingPhraseStore.daysUntilNextReview(for: card.id) {
            statusMessage = days <= 0
                ? "继续保持：\(card.english)，今天稍后再复习一次"
                : "继续保持：\(card.english)，下次复习在 \(days) 天后"
        } else {
            statusMessage = "继续保持：\(card.english)，已毕业，不再安排复习"
        }
    }

    func forgotCurrentMeetingPhrase() {
        guard let card = currentMeetingPhraseCard else { return }
        guard card.isReview else { return }

        meetingPhraseStore.resetReview(word: card.id)
        refreshMeetingPhrasesIfNeeded()
        statusMessage = "重置进度：\(card.english)，明天再复习一次"
    }

    // MARK: - 中译英产出 + AI 批改

    private func loadProductionDrillState() {
        let bank = ProductionDrillBank.all
        guard !bank.isEmpty else {
            currentDrill = nil
            return
        }
        let storedIndex = defaults.integer(forKey: Self.drillIndexKey)
        drillIndex = ((storedIndex % bank.count) + bank.count) % bank.count
        currentDrill = bank[drillIndex]

        if let data = defaults.data(forKey: Self.drillDatesKey),
           let dates = try? JSONDecoder().decode([Date].self, from: data) {
            productionDrillDates = dates
        }
        recomputeDrillsGradedToday()
    }

    private func recomputeDrillsGradedToday() {
        drillsGradedToday = productionDrillDates.filter { calendar.isDateInToday($0) }.count
    }

    /// Move to the next drill, clearing the current attempt + grade.
    func nextDrill() {
        let bank = ProductionDrillBank.all
        guard !bank.isEmpty else { return }
        drillIndex = (drillIndex + 1) % bank.count
        currentDrill = bank[drillIndex]
        drillInput = ""
        drillGrade = nil
        drillGradeError = nil
        defaults.set(drillIndex, forKey: Self.drillIndexKey)
    }

    /// Send the current attempt to the configured Claude engine for grading.
    func gradeCurrentDrill() async {
        guard let drill = currentDrill else { return }
        let attempt = drillInput.trimmed
        guard !attempt.isEmpty else {
            drillGradeError = "先写下你的英文作答再提交批改"
            return
        }

        isGradingDrill = true
        drillGrade = nil
        drillGradeError = nil
        defer { isGradingDrill = false }

        do {
            let grade = try await translationService.gradeProduction(
                chinese: drill.chinese,
                reference: drill.reference,
                attempt: attempt
            )
            drillGrade = grade
            recordDrillAttempt()
            statusMessage = "已批改：\(drill.chinese)"
        } catch {
            drillGradeError = (error as? LocalizedError)?.errorDescription
                ?? "批改失败：\(error.localizedDescription)"
        }
    }

    private func recordDrillAttempt() {
        productionDrillDates.append(Date())
        if productionDrillDates.count > 2000 {
            productionDrillDates.removeFirst(productionDrillDates.count - 2000)
        }
        if let data = try? JSONEncoder().encode(productionDrillDates) {
            defaults.set(data, forKey: Self.drillDatesKey)
        }
        recomputeDrillsGradedToday()
        refreshDockBadge()
    }

    /// Whether grading is possible right now (an AI engine is configured).
    var canGradeProduction: Bool {
        translationEngine != .freeOnly
    }

    /// Whether a looked-up result can be added to the word-learning deck. Only
    /// single English words qualify — the deck and its SRS are word-based.
    func canAddLookupToLearning(_ result: TranslationResult) -> Bool {
        Self.singleEnglishWord(from: result.originalText) != nil
    }

    /// Outcome of adding a lookup to the learning deck, paired with the word so
    /// callers can build a message. `.ineligible` means the lookup wasn't a
    /// single English word.
    enum LearningAddResult {
        case added(String)
        case alreadyLearning(String)
        case alreadyMastered(String)
        case ineligible

        var statusMessage: String {
            switch self {
            case .added(let w): return "已加入生词本：\(w)，进入每日学习与复习"
            case .alreadyLearning(let w): return "\(w) 已在学习列表中"
            case .alreadyMastered(let w): return "\(w) 已经掌握啦，如需重学可在「累计熟悉」里取消熟悉"
            case .ineligible: return "只能把单个英文单词加入生词本"
            }
        }

        var feedbackTitle: String {
            switch self {
            case .added: return "已加入生词本"
            case .alreadyLearning: return "已在学习中"
            case .alreadyMastered: return "已经掌握"
            case .ineligible: return "无法加入"
            }
        }

        var feedbackMessage: String {
            switch self {
            case .added(let w): return "\(w) 已进入每日学习与复习"
            case .alreadyLearning(let w): return "\(w) 已经在学习列表里了"
            case .alreadyMastered(let w): return "\(w) 已掌握，可在「累计熟悉」取消熟悉重学"
            case .ineligible: return "只能加入单个英文单词"
            }
        }
    }

    /// Add a looked-up word to the daily learning deck + SRS. The translation we
    /// already have is cached so the word card renders instantly without a
    /// second network round-trip.
    @discardableResult
    private func performAddToLearning(_ result: TranslationResult) -> LearningAddResult {
        guard let word = Self.singleEnglishWord(from: result.originalText) else {
            return .ineligible
        }

        if wordDefinitionCache[word] == nil {
            wordDefinitionCache[word] = result
        }

        let outcome = wordCarouselStore.addToLearning(word: word)
        refreshWordCarouselIfNeeded()

        switch outcome {
        case .added: return .added(word)
        case .alreadyLearning: return .alreadyLearning(word)
        case .alreadyMastered: return .alreadyMastered(word)
        }
    }

    /// Used by the main window / quick-translate panel, which surface feedback
    /// through `statusMessage` and their own inline UI.
    @discardableResult
    func addLookupToLearning(_ result: TranslationResult) -> Bool {
        let outcome = performAddToLearning(result)
        statusMessage = outcome.statusMessage
        if case .added = outcome { return true }
        return false
    }

    /// Used by the floating desktop-pet bubble: shows a result bubble so the
    /// click has visible success/failure feedback even with no main window open.
    func addLookupToLearningFromBubble(_ result: TranslationResult) {
        let outcome = performAddToLearning(result)
        statusMessage = outcome.statusMessage
        popoverController.presentFeedback(
            title: outcome.feedbackTitle,
            message: outcome.feedbackMessage
        )
    }

    /// Normalizes a single English word (letters, optional internal `-`/`'`) to
    /// lowercase. Returns `nil` for phrases, sentences, or non-Latin text.
    private static func singleEnglishWord(from text: String) -> String? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        guard !trimmed.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else { return nil }

        let allowed = CharacterSet.letters
            .union(CharacterSet(charactersIn: "-'"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        // Require at least one ASCII letter so non-Latin strings are rejected.
        let asciiLetters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard trimmed.unicodeScalars.contains(where: { asciiLetters.contains($0) }) else {
            return nil
        }
        return trimmed.lowercased()
    }

    /// Read text aloud via the shared SpeechService. Used by the speaker
    /// buttons on the daily word card and the translation result card.
    func speak(_ text: String) {
        speechService.speak(text)
    }

    /// Forward the current Claude API key + model into the translation
    /// service actor. Called at startup and whenever settings change.
    private func pushClaudeConfiguration() {
        let engine = translationEngine
        let apiKey = claudeAPIKey
        let model = claudeModel
        Task {
            await translationService.updateConfiguration(engine: engine, apiKey: apiKey, model: model)
        }
    }

    func requestAccessibilityPermission() {
        let granted = selectedTextService.requestAccessibilityPermission()
        let wasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = granted
        if granted {
            statusMessage = "辅助功能权限已就绪"
            if !wasGranted {
                hotkeyManager.reRegisterIfNeeded()
            }
        } else {
            statusMessage = "请在 系统设置 -> 隐私与安全性 -> 辅助功能 中允许本应用（若已允许，请返回本应用稍等一下）"
        }
    }

    func syncDesktopPetVisibility() {
        switch translationPresentationMode {
        case .floating:
            popoverController.showDesktopPet()
        case .mainWindow:
            popoverController.hideDesktopPet()
        }
    }

    /// Re-show the last floating translation when the user right-clicks the pet.
    private func showLastTranslationBubble() {
        guard let last = lastFloatingResult else {
            popoverController.presentFeedback(title: "还没有翻译", message: "选中文本按 ⌘C⌘C 试试")
            return
        }
        popoverController.present(
            result: last.result,
            sourceAppName: last.sourceApp,
            near: bestPopoverPosition()
        )
    }

    private func showDesktopDailyWordInvite() {
        guard translationPresentationMode == .floating else { return }

        if hasCompletedDailyWordTarget {
            popoverController.presentDailyWordCompletion(
                message: DailyWordProgress.completionMessage(
                    quota: todayDailyWordTarget,
                    groupSize: Self.dailyWordQuota
                )
            )
            return
        }

        guard let card = currentDailyWordCard else {
            popoverController.presentFeedback(
                title: "今日单词",
                message: "今天暂无可学习单词"
            )
            return
        }

        popoverController.presentDailyWordInvite(card: card)
    }

    private func completeDesktopDailyWord(_ card: DesktopWordCard) {
        guard currentDailyWordCard?.word == card.word else {
            showDesktopDailyWordInvite()
            return
        }

        if card.isReview {
            rememberCurrentWord()
            presentDailyWordFeedbackAndAdvance(title: "复习完成", message: "\(card.word) 已进入下次复习")
        } else {
            markCurrentWordAsMastered()
            presentDailyWordFeedbackAndAdvance(title: "记住了", message: "\(card.word) 已加入复习节奏")
        }
    }

    private func practiceDesktopDailyWord(_ card: DesktopWordCard) {
        guard currentDailyWordCard?.word == card.word else {
            showDesktopDailyWordInvite()
            return
        }

        if card.isReview {
            forgotCurrentWord()
        } else {
            markCurrentWordNeedsPractice()
        }
        presentDailyWordFeedbackAndAdvance(title: "不熟悉", message: "\(card.word) 已完成今日学习，后续会加强复习")
    }

    private func presentDailyWordFeedbackAndAdvance(title: String, message: String) {
        popoverController.presentFeedback(
            title: title,
            message: message,
            autoDismissAfter: DesktopPetBubbleTiming.dailyWordFeedbackAutoAdvanceSeconds
        ) { [weak self] in
            self?.showDesktopDailyWordInvite()
        }
    }

    func translateFromManualInput() {
        let text = manualInput.trimmed
        guard !text.isEmpty else {
            statusMessage = "请输入要翻译的内容"
            return
        }
        let direction = manualDirectionChoice.concreteDirection

        Task {
            await translateAndRecord(text: text, sourceApp: "Manual Input", presentation: .none, direction: direction)
        }
    }

    func translateManualText(_ text: String) async {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else {
            statusMessage = "请输入要翻译的英文内容"
            return
        }
        await translateAndRecord(text: trimmed, sourceApp: "Menubar", presentation: .none)
    }

    func showHistoryItem(_ item: LookupHistoryItem) {
        latestResult = TranslationResult(
            originalText: item.rawText,
            translatedText: item.translation,
            phonetic: item.phonetic,
            explanations: item.explanations,
            provider: item.provider ?? "历史记录",
            direction: TranslationService.detectDirection(item.rawText)
        )
        latestLookupContext = item.context
        statusMessage = "已加载历史记录：\(item.rawText)"
    }

    func translateSelectionNow() {
        Task {
            await handleHotkeyTriggeredTranslation()
        }
    }

    /// Called from `ServicesProvider` when the user picks "用 Nova 翻译"
    /// in the system Services menu. The source app is hard to identify from
    /// outside the process, so we tag it generically as "Services 菜单".
    func translateFromServicesMenu(text: String) {
        NSApp.setActivationPolicy(.regular)
        let presentation = translationPresentationMode
        Task { @MainActor in
            await translateAndRecord(
                text: text,
                sourceApp: "Services 菜单",
                presentation: presentation
            )
        }
    }

    /// Used by `QuickTranslatePopoverView` — translates, records history, and
    /// returns the result so the panel can display it inline. Does not route
    /// through `PresentationTarget` because the panel manages its own result UI.
    func translateForQuickPanel(_ text: String, direction: TranslationDirection? = nil) async -> TranslationResult? {
        let cleaned = text.trimmed
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.count <= TranslationLimits.maxCharacters else {
            statusMessage = "一次最多翻译 \(TranslationLimits.maxCharacters) 个字符"
            return nil
        }
        do {
            let outcome = try await translationService.translate(cleaned, direction: direction)
            if let historyStore {
                try historyStore.insertLookup(
                    rawText: cleaned,
                    sourceApp: "Quick Translate",
                    context: nil,
                    result: outcome.result
                )
                history = try historyStore.fetchRecent(limit: 300)
            }
            latestResult = outcome.result
            return outcome.result
        } catch {
            statusMessage = "翻译失败：\(error.localizedDescription)"
            return nil
        }
    }

    func refreshPermissionStatus() {
        let granted = selectedTextService.isAccessibilityTrusted()
        let wasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = granted
        if granted && !wasGranted {
            hotkeyManager.reRegisterIfNeeded()
        }
    }

    func refreshHistory() async {
        guard let historyStore else { return }
        do {
            history = try historyStore.fetchRecent(limit: 300)
        } catch {
            statusMessage = "读取历史失败：\(error.localizedDescription)"
        }
    }

    func deleteHistory(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        guard let historyStore else { return }

        do {
            try historyStore.deleteHistory(ids: ids)
            history = try historyStore.fetchRecent(limit: 300)
            statusMessage = "已删除 \(ids.count) 条记录"
        } catch {
            statusMessage = "删除记录失败：\(error.localizedDescription)"
        }
    }

    func selectInterestTopic(_ topic: InterestTopic) {
        guard selectedTopic != topic else { return }
        selectedTopic = topic
        lessonSeedOffset = 0
        refreshLessonForSelectedTopic()
        statusMessage = "已切换到 \(topic.title) 学习流"
    }

    func refreshCurrentLesson() {
        let totalTemplates = (Self.lessonTemplates[selectedTopic]?.count ?? 0)
        let wrap = max(totalTemplates, 1)
        lessonSeedOffset = (lessonSeedOffset &+ 1) % wrap
        refreshLessonForSelectedTopic()
        statusMessage = isCurrentTopicExhausted
            ? "当前主题题目已全部答对，可切换主题继续学习"
            : "已生成新的 \(selectedTopic.title) 内容"
    }

    func chooseLessonOption(_ optionIndex: Int) {
        lessonSelectedOptionIndex = optionIndex
    }

    func submitLessonAnswer() {
        guard let lessonSelectedOptionIndex else {
            lessonFeedbackMessage = "先选择一个答案再提交。"
            return
        }

        let isCorrect = lessonSelectedOptionIndex == currentLesson.answerIndex
        recordLessonAttempt(selectedOptionIndex: lessonSelectedOptionIndex, isCorrect: isCorrect)

        if isCorrect {
            registerLessonCompletion()
            lessonFeedbackMessage = "回答正确。\(currentLesson.explanation)"
        } else {
            let correct = currentLesson.options[currentLesson.answerIndex]
            lessonFeedbackMessage = "还差一点。正确答案是：\(correct)。\(currentLesson.explanation)"
        }
    }

    func refreshDailyCompletionState() {
        if let lastCompletedLearningDate {
            hasCompletedLearningToday = calendar.isDateInToday(lastCompletedLearningDate)
        } else {
            hasCompletedLearningToday = false
        }
        refreshWordCarouselIfNeeded()
        refreshMeetingPhrasesIfNeeded()
        recomputeDrillsGradedToday()
    }

    /// Apply a change coming from the reminder settings UI.
    func updateReminderSettings(enabled: Bool, time: Date) async {
        reminderTime = time
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 20
        let minute = components.minute ?? 0

        defaults.set(hour, forKey: Self.reminderHourKey)
        defaults.set(minute, forKey: Self.reminderMinuteKey)

        if enabled {
            let granted = await reminderScheduler.requestAuthorizationIfNeeded()
            if granted {
                reminderEnabled = true
                defaults.set(true, forKey: Self.reminderEnabledKey)
                reminderScheduler.schedule(hour: hour, minute: minute)
                if hasCompletedLearningToday {
                    reminderScheduler.suppressForToday(hour: hour, minute: minute)
                }
                statusMessage = "每日提醒已开启，时间 \(String(format: "%02d:%02d", hour, minute))"
            } else {
                reminderEnabled = false
                defaults.set(false, forKey: Self.reminderEnabledKey)
                statusMessage = "通知权限未授予，请在 系统设置 -> 通知 中允许 Nova 发送通知"
            }
        } else {
            reminderEnabled = false
            defaults.set(false, forKey: Self.reminderEnabledKey)
            reminderScheduler.cancel()
            statusMessage = "已关闭每日提醒"
        }
    }

    private static func defaultReminderTime() -> Date {
        makeReminderTime(hour: 20, minute: 0)
    }

    private static func makeReminderTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func loadWordDefinitionIfNeeded(for word: String) {
        if let cached = wordDefinitionCache[word] {
            updateDailyWordCard(word: word, with: cached)
            return
        }

        if loadingWordDefinitions.contains(word) {
            return
        }

        loadingWordDefinitions.insert(word)

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.loadingWordDefinitions.remove(word)
            }

            do {
                let outcome = try await self.translationService.translate(word)
                self.wordDefinitionCache[word] = outcome.result
                self.updateDailyWordCard(word: word, with: outcome.result)
            } catch {
                self.updateDailyWordCardAsFallback(word: word)
            }
        }
    }

    private func updateDailyWordCard(word: String, with definition: TranslationResult) {
        guard let index = dailyWordCards.firstIndex(where: { $0.word == word }) else { return }
        var card = dailyWordCards[index]
        Self.applyDefinition(definition, to: &card)
        dailyWordCards[index] = card
    }

    private func updateDailyWordCardAsFallback(word: String) {
        guard let index = dailyWordCards.firstIndex(where: { $0.word == word }) else { return }
        var card = dailyWordCards[index]
        card.meaning = "暂时无法加载词义"
        card.explanation = "网络异常时可稍后重试"
        card.provider = "Fallback"
        dailyWordCards[index] = card
    }

    private static func applyDefinition(_ definition: TranslationResult, to card: inout DesktopWordCard) {
        card.meaning = definition.translatedText
        card.phonetic = definition.phonetic
        card.explanation = definition.explanations.first ?? "常用词，建议结合例句记忆"
        card.provider = definition.provider
    }

    private func handleHotkeyTriggeredTranslation() async {
        // Always make sure the app is running as a regular app so the menubar
        // extra still responds and the popover panel can come to the front.
        // Do NOT `.activate(ignoringOtherApps: true)` here — we want to avoid
        // stealing focus when the user is in floating-popup mode.
        NSApp.setActivationPolicy(.regular)

        let presentation = translationPresentationMode

        do {
            hasAccessibilityPermission = selectedTextService.isAccessibilityTrusted()

            if hasAccessibilityPermission {
                let snapshot = try selectedTextService.fetchSelectedText()
                await translateAndRecord(
                    text: snapshot.text,
                    sourceApp: snapshot.sourceAppName,
                    context: snapshot.context,
                    presentation: presentation
                )
                return
            }
        } catch {
            // 选中文本读取失败时自动回退到剪贴板
        }

        if let clipboardText = NSPasteboard.general.string(forType: .string),
           !clipboardText.trimmed.isEmpty {
            await translateAndRecord(
                text: clipboardText,
                sourceApp: "Clipboard",
                presentation: presentation
            )
            statusMessage = hasAccessibilityPermission
                ? "未读到选中文本，已回退使用剪贴板内容"
                : "已使用剪贴板内容翻译（如需直接取选中文本，请授权辅助功能）"
            return
        }

        statusMessage = "没有读取到选中文本，请先选中英文单词或句子"
    }

    private enum PresentationTarget {
        case floating
        case mainWindow
        case none
    }

    private func translateAndRecord(
        text: String,
        sourceApp: String?,
        context: String? = nil,
        presentation: PresentationTarget,
        direction: TranslationDirection? = nil
    ) async {
        let cleanedText = text.trimmed
        guard !cleanedText.isEmpty else {
            statusMessage = "内容为空，无法翻译"
            if presentation == .floating {
                popoverController.presentFeedback(title: "没有内容", message: "先选中文本再试一次")
            }
            return
        }

        if cleanedText.count > TranslationLimits.maxCharacters {
            statusMessage = "一次最多翻译 \(TranslationLimits.maxCharacters) 个字符，再长建议分段"
            if presentation == .floating {
                popoverController.presentFeedback(
                    title: "内容太长",
                    message: "一次最多翻译 \(TranslationLimits.maxCharacters) 个字符"
                )
            }
            return
        }

        if presentation == .floating {
            popoverController.presentTranslating(text: cleanedText, near: bestPopoverPosition())
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let outcome = try await translationService.translate(cleanedText, direction: direction)
            latestResult = outcome.result
            latestLookupContext = context

            if let historyStore {
                try historyStore.insertLookup(
                    rawText: cleanedText,
                    sourceApp: sourceApp,
                    context: context,
                    result: outcome.result
                )
                history = try historyStore.fetchRecent(limit: 300)
            }

            // Online down + local dict miss surfaces as a "Fallback" provider.
            // Treat that as a retryable failure so the user can re-fire the
            // same lookup once the network comes back.
            let isFallbackOnly = outcome.result.provider.hasPrefix("Fallback")
            if isFallbackOnly {
                lastFailedRequest = PendingRetryRequest(
                    text: cleanedText,
                    sourceApp: sourceApp,
                    context: context,
                    presentation: presentation,
                    direction: direction
                )
                pendingRetry = true
            } else {
                lastFailedRequest = nil
                pendingRetry = false
            }

            if let notice = outcome.onlineNotice {
                statusMessage = isFallbackOnly
                    ? "\(notice) 网络恢复后可点 statusCard 的「重试」"
                    : notice
            } else if let sourceApp {
                statusMessage = "已翻译并记录（来源：\(sourceApp)）"
            } else {
                statusMessage = "已翻译并记录"
            }

            switch presentation {
            case .floating:
                lastFloatingResult = (outcome.result, sourceApp)
                popoverController.present(result: outcome.result, sourceAppName: sourceApp, near: bestPopoverPosition())
            case .mainWindow:
                openMainWindow()
            case .none:
                break
            }
        } catch {
            lastFailedRequest = PendingRetryRequest(
                text: cleanedText,
                sourceApp: sourceApp,
                context: context,
                presentation: presentation,
                direction: direction
            )
            pendingRetry = true
            statusMessage = "翻译失败：\(error.localizedDescription) — 可点 statusCard 的「重试」"
            if presentation == .floating {
                popoverController.presentFeedback(title: "翻译失败", message: "稍后再试，或到主窗口重试")
            }
        }
    }

    /// Re-run the last failed translation request, preserving its source and
    /// presentation target. No-op if there is nothing to retry.
    func retryLastTranslation() async {
        guard let request = lastFailedRequest else { return }
        await translateAndRecord(
            text: request.text,
            sourceApp: request.sourceApp,
            context: request.context,
            presentation: request.presentation,
            direction: request.direction
        )
    }

    /// Overload used by callers that already speak `TranslationPresentation`.
    private func translateAndRecord(
        text: String,
        sourceApp: String?,
        context: String? = nil,
        presentation: TranslationPresentation,
        direction: TranslationDirection? = nil
    ) async {
        let target: PresentationTarget = presentation == .floating ? .floating : .mainWindow
        await translateAndRecord(text: text, sourceApp: sourceApp, context: context, presentation: target, direction: direction)
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = Self.primaryWindow() {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // On first launch the SwiftUI WindowGroup may not have materialised a
        // window yet. Retry after a short delay; if it still isn't there, the
        // user can open it from the desktop pet menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let window = Self.primaryWindow() {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private static func primaryWindow() -> NSWindow? {
        // Utility popovers are NSWindows too; filter to windows that look like
        // real document/content windows.
        for window in NSApp.windows where window.canBecomeMain && window.title == "Nova" {
            return window
        }
        for window in NSApp.windows where window.canBecomeMain && !window.title.isEmpty {
            return window
        }
        return nil
    }

    /// Best-effort screen position near the frontmost window's upper-center.
    /// Uses `CGWindowListCopyWindowInfo` — no Accessibility permission needed.
    static func frontmostWindowPosition() -> NSPoint? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // Find the first on-screen window belonging to the frontmost app.
        guard let winInfo = windowList.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }) else { return nil }

        guard let bounds = winInfo[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let w = bounds["Width"], let h = bounds["Height"],
              w > 50, h > 50
        else { return nil }

        // CG coords (top-left origin) → AppKit (bottom-left origin).
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        // Return a point in the upper-third, horizontally centered.
        return NSPoint(
            x: x + w * 0.5,
            y: screenHeight - (y + h * 0.3)
        )
    }

    /// Determine the best screen position to show a floating panel, using a
    /// three-tier fallback: text cursor → frontmost window → mouse pointer.
    func bestPopoverPosition() -> NSPoint {
        if let cursorPos = selectedTextService.focusedElementCursorPosition() {
            return cursorPos
        }
        if let windowPos = Self.frontmostWindowPosition() {
            return windowPos
        }
        return NSEvent.mouseLocation
    }

    private func refreshLessonForSelectedTopic() {
        let templates = Self.lessonTemplates[selectedTopic] ?? [Self.fallbackTemplate(for: selectedTopic)]
        let mastered = masteredTemplateIDs(for: selectedTopic)
        var availableTemplates = templates.filter { !mastered.contains($0.id) }

        if availableTemplates.isEmpty {
            isCurrentTopicExhausted = true
            availableTemplates = templates
        } else {
            isCurrentTopicExhausted = false
        }

        if availableTemplates.count > 1 {
            let currentTemplate = currentLesson.templateID
            availableTemplates.removeAll { $0.id == currentTemplate }
            if availableTemplates.isEmpty {
                availableTemplates = templates.filter { !mastered.contains($0.id) }
            }
            if availableTemplates.isEmpty {
                availableTemplates = templates
            }
        }

        let dayIndex = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let index = abs(dayIndex + lessonSeedOffset) % availableTemplates.count
        let selected = availableTemplates[index]

        currentLesson = Self.makeLesson(topic: selectedTopic, template: selected)
        currentLessonIsReview = isTemplateReviewCandidate(selected.id)
        lessonSelectedOptionIndex = nil
        lessonFeedbackMessage = isCurrentTopicExhausted
            ? "当前主题题目已全部答对，可切换主题，或回顾下方已学题目。"
            : "阅读短文后选一个答案，完成今天的 3 分钟学习。"
    }

    private func recordLessonAttempt(selectedOptionIndex: Int, isCorrect: Bool) {
        let correctOption = currentLesson.options[currentLesson.answerIndex]
        let selectedOption = currentLesson.options[selectedOptionIndex]
        let now = Date()

        let record = LearningAttemptRecord(
            id: UUID(),
            lessonTemplateID: currentLesson.templateID,
            topicRawValue: currentLesson.topic.rawValue,
            lessonTitle: currentLesson.title,
            question: currentLesson.question,
            selectedOption: selectedOption,
            correctOption: correctOption,
            isCorrect: isCorrect,
            isReview: currentLessonIsReview,
            createdAt: now
        )

        learningAttempts.insert(record, at: 0)
        if learningAttempts.count > 600 {
            learningAttempts.removeLast(learningAttempts.count - 600)
        }

        var state = lessonProgressStates[currentLesson.templateID] ?? LessonProgressState(
            topicRawValue: currentLesson.topic.rawValue,
            lessonTitle: currentLesson.title,
            question: currentLesson.question,
            hasWrongAttempt: false,
            isMastered: false,
            attempts: 0,
            lastAttemptAt: now
        )

        state.topicRawValue = currentLesson.topic.rawValue
        state.lessonTitle = currentLesson.title
        state.question = currentLesson.question
        state.attempts += 1
        state.lastAttemptAt = now
        if isCorrect {
            state.isMastered = true
        } else {
            state.hasWrongAttempt = true
        }

        lessonProgressStates[currentLesson.templateID] = state
        persistLearningProgress()
    }

    private func masteredTemplateIDs(for topic: InterestTopic) -> Set<String> {
        let ids = lessonProgressStates.compactMap { templateID, state in
            (state.topicRawValue == topic.rawValue && state.isMastered) ? templateID : nil
        }
        return Set(ids)
    }

    private func isTemplateReviewCandidate(_ templateID: String) -> Bool {
        guard let state = lessonProgressStates[templateID] else {
            return false
        }
        return state.hasWrongAttempt && !state.isMastered
    }

    private func registerLessonCompletion() {
        completedLearningCards += 1

        let today = calendar.startOfDay(for: Date())
        let lastDate = lastCompletedLearningDate

        if let lastDate {
            let normalizedLastDate = calendar.startOfDay(for: lastDate)
            if calendar.isDate(normalizedLastDate, inSameDayAs: today) {
                // 同一天内多次完成，仅增加完成次数，不重复增加连胜
            } else if let diff = calendar.dateComponents([.day], from: normalizedLastDate, to: today).day,
                      diff == 1 {
                learningStreakDays += 1
            } else {
                learningStreakDays = 1
            }
        } else {
            learningStreakDays = 1
        }

        lastCompletedLearningDate = today
        hasCompletedLearningToday = true
        persistLearningProgress()

        if reminderEnabled {
            let components = calendar.dateComponents([.hour, .minute], from: reminderTime)
            reminderScheduler.suppressForToday(
                hour: components.hour ?? 20,
                minute: components.minute ?? 0
            )
        }
    }

    private func persistLearningProgress() {
        defaults.set(completedLearningCards, forKey: Self.completedCardsKey)
        defaults.set(learningStreakDays, forKey: Self.learningStreakDaysKey)
        if let lastCompletedLearningDate {
            defaults.set(lastCompletedLearningDate, forKey: Self.lastCompletedDateKey)
        } else {
            defaults.removeObject(forKey: Self.lastCompletedDateKey)
        }

        do {
            let attemptsData = try JSONEncoder().encode(learningAttempts)
            defaults.set(attemptsData, forKey: Self.learningAttemptsKey)
        } catch {
            NSLog("[AppModel] failed to persist learningAttempts: %@", error.localizedDescription)
            statusMessage = "学习记录保存失败，请查看日志"
        }
        do {
            let stateData = try JSONEncoder().encode(lessonProgressStates)
            defaults.set(stateData, forKey: Self.lessonProgressStatesKey)
        } catch {
            NSLog("[AppModel] failed to persist lessonProgressStates: %@", error.localizedDescription)
            statusMessage = "学习进度保存失败，请查看日志"
        }
    }

    private func loadLearningProgress() {
        completedLearningCards = defaults.integer(forKey: Self.completedCardsKey)
        learningStreakDays = defaults.integer(forKey: Self.learningStreakDaysKey)
        lastCompletedLearningDate = defaults.object(forKey: Self.lastCompletedDateKey) as? Date

        if let attemptsData = defaults.data(forKey: Self.learningAttemptsKey),
           let decodedAttempts = try? JSONDecoder().decode([LearningAttemptRecord].self, from: attemptsData) {
            learningAttempts = decodedAttempts.sorted { $0.createdAt > $1.createdAt }
        } else {
            learningAttempts = []
        }

        if let stateData = defaults.data(forKey: Self.lessonProgressStatesKey),
           let decodedStates = try? JSONDecoder().decode([String: LessonProgressState].self, from: stateData) {
            lessonProgressStates = decodedStates
        } else {
            lessonProgressStates = [:]
        }

        if lessonProgressStates.isEmpty, !learningAttempts.isEmpty {
            rebuildLessonProgressFromAttempts()
            persistLearningProgress()
        }

        refreshDailyCompletionState()
    }

    private func rebuildLessonProgressFromAttempts() {
        var rebuilt: [String: LessonProgressState] = [:]

        for attempt in learningAttempts.sorted(by: { $0.createdAt < $1.createdAt }) {
            var state = rebuilt[attempt.lessonTemplateID] ?? LessonProgressState(
                topicRawValue: attempt.topicRawValue,
                lessonTitle: attempt.lessonTitle,
                question: attempt.question,
                hasWrongAttempt: false,
                isMastered: false,
                attempts: 0,
                lastAttemptAt: attempt.createdAt
            )

            state.topicRawValue = attempt.topicRawValue
            state.lessonTitle = attempt.lessonTitle
            state.question = attempt.question
            state.attempts += 1
            state.lastAttemptAt = attempt.createdAt
            if attempt.isCorrect {
                state.isMastered = true
            } else {
                state.hasWrongAttempt = true
            }

            rebuilt[attempt.lessonTemplateID] = state
        }

        lessonProgressStates = rebuilt
    }

    private struct LessonTemplate {
        let id: String
        let title: String
        let warmup: String
        let passage: String
        let phrases: [LessonPhrase]
        let question: String
        let options: [String]
        let answerIndex: Int
        let explanation: String
    }

    private static func makeLesson(topic: InterestTopic, seed: Int) -> InterestLesson {
        let templates = lessonTemplates[topic] ?? [fallbackTemplate(for: topic)]
        let dayIndex = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let index = abs(dayIndex + seed) % templates.count
        let selected = templates[index]

        return makeLesson(topic: topic, template: selected)
    }

    private static func makeLesson(topic: InterestTopic, template: LessonTemplate) -> InterestLesson {
        return InterestLesson(
            templateID: template.id,
            topic: topic,
            title: template.title,
            warmup: template.warmup,
            passage: template.passage,
            phrases: template.phrases,
            question: template.question,
            options: template.options,
            answerIndex: template.answerIndex,
            explanation: template.explanation
        )
    }

    private static func fallbackTemplate(for topic: InterestTopic) -> LessonTemplate {
        LessonTemplate(
            id: "\(topic.rawValue)-fallback",
            title: "\(topic.title) 速读",
            warmup: "先读 45 秒，再大声复述 1 句。",
            passage: "Learning with your interests makes practice easier and more consistent.",
            phrases: [
                LessonPhrase(
                    english: "consistent",
                    chinese: "持续的",
                    example: "Small and consistent steps beat random hard work."
                )
            ],
            question: "哪句话更符合上面短文？",
            options: [
                "兴趣学习会降低学习持续性",
                "兴趣学习能让练习更容易坚持",
                "兴趣学习不需要复习"
            ],
            answerIndex: 1,
            explanation: "兴趣能提高投入感，从而更容易坚持每天练习。"
        )
    }

    private static let lessonTemplates: [InterestTopic: [LessonTemplate]] = [
        .movies: [
            LessonTemplate(
                id: "movies-trailer",
                title: "电影预告片跟读",
                warmup: "想象你在给朋友推荐一部电影。",
                passage: "The trailer opens with a quiet city, then a sudden explosion changes everything. The hero does not trust anyone, but she keeps moving forward to protect her family.",
                phrases: [
                    LessonPhrase(
                        english: "opens with",
                        chinese: "以...开场",
                        example: "The story opens with a rainy night."
                    ),
                    LessonPhrase(
                        english: "keep moving forward",
                        chinese: "继续向前",
                        example: "Even when it is hard, keep moving forward."
                    )
                ],
                question: "这段预告片主角的核心状态是什么？",
                options: [
                    "她马上放弃任务",
                    "她在怀疑中继续保护家人",
                    "她计划离开城市旅行"
                ],
                answerIndex: 1,
                explanation: "文中明确提到她不信任任何人但仍继续前进保护家人。"
            ),
            LessonTemplate(
                id: "movies-review",
                title: "影评一句话复述",
                warmup: "用英语说一句你最近看过的电影评价。",
                passage: "I expected a simple comedy, but the film surprised me with emotional depth. The dialogue felt natural, and the ending stayed in my mind after I left the theater.",
                phrases: [
                    LessonPhrase(
                        english: "emotional depth",
                        chinese: "情感深度",
                        example: "The novel has emotional depth."
                    ),
                    LessonPhrase(
                        english: "stayed in my mind",
                        chinese: "让我久久难忘",
                        example: "Her speech stayed in my mind all week."
                    )
                ],
                question: "作者为什么对这部电影印象深刻？",
                options: [
                    "演员阵容非常豪华",
                    "电影节奏很快",
                    "对白自然且结尾令人难忘"
                ],
                answerIndex: 2,
                explanation: "关键词是 dialogue felt natural 与 ending stayed in my mind。"
            )
        ],
        .technology: [
            LessonTemplate(
                id: "tech-news",
                title: "科技新闻速读",
                warmup: "想象你在团队晨会上汇报一条科技动态。",
                passage: "Our team launched a small AI feature last week. Users adopted it quickly because it reduced repetitive tasks and gave instant suggestions during writing.",
                phrases: [
                    LessonPhrase(
                        english: "adopt quickly",
                        chinese: "快速采用",
                        example: "Customers adopt quickly when the workflow is simple."
                    ),
                    LessonPhrase(
                        english: "repetitive tasks",
                        chinese: "重复性任务",
                        example: "Automation saves us from repetitive tasks."
                    )
                ],
                question: "用户为什么会快速采用这个功能？",
                options: [
                    "因为界面颜色更好看",
                    "因为减少重复任务并提供即时建议",
                    "因为发布会规模很大"
                ],
                answerIndex: 1,
                explanation: "原文给出的直接原因是效率提升与即时建议。"
            ),
            LessonTemplate(
                id: "tech-update",
                title: "产品迭代表达",
                warmup: "练习一句常见工作表达：We shipped an update.",
                passage: "We shipped an update with better search relevance. Instead of adding many buttons, we simplified the flow so new users can finish onboarding in two minutes.",
                phrases: [
                    LessonPhrase(
                        english: "search relevance",
                        chinese: "搜索相关性",
                        example: "We improved search relevance with cleaner tags."
                    ),
                    LessonPhrase(
                        english: "onboarding",
                        chinese: "新手引导",
                        example: "Good onboarding reduces early confusion."
                    )
                ],
                question: "这次更新最核心的设计动作是什么？",
                options: [
                    "增加更多按钮",
                    "简化流程以缩短上手时间",
                    "移除搜索能力"
                ],
                answerIndex: 1,
                explanation: "Instead of adding many buttons, we simplified the flow。"
            )
        ],
        .travel: [
            LessonTemplate(
                id: "travel-plan",
                title: "旅行计划表达",
                warmup: "想象你正在和朋友讨论周末短途旅行。",
                passage: "We left early to catch the first train and reached the old town before noon. The streets were quiet, so we explored local cafes and walked along the river.",
                phrases: [
                    LessonPhrase(
                        english: "catch the first train",
                        chinese: "赶第一班火车",
                        example: "If we catch the first train, we can avoid crowds."
                    ),
                    LessonPhrase(
                        english: "old town",
                        chinese: "老城区",
                        example: "The old town has great food and history."
                    )
                ],
                question: "他们为什么能在中午前到达？",
                options: [
                    "因为提前出发赶第一班车",
                    "因为住在老城区",
                    "因为取消了行程"
                ],
                answerIndex: 0,
                explanation: "原文第一句给出原因：left early to catch the first train。"
            ),
            LessonTemplate(
                id: "travel-airport",
                title: "机场沟通表达",
                warmup: "练习问路句型：Could you tell me where ... is?",
                passage: "At the airport, I asked a staff member where gate C18 was. She gave clear directions, and I arrived at the boarding area with plenty of time.",
                phrases: [
                    LessonPhrase(
                        english: "clear directions",
                        chinese: "清晰指引",
                        example: "Clear directions save time in large airports."
                    ),
                    LessonPhrase(
                        english: "plenty of time",
                        chinese: "充足时间",
                        example: "We arrived early and had plenty of time."
                    )
                ],
                question: "作者最后处于什么状态？",
                options: [
                    "赶不上登机",
                    "时间充裕地到达登机区",
                    "找不到航站楼"
                ],
                answerIndex: 1,
                explanation: "with plenty of time 表示时间充裕。"
            )
        ],
        .gaming: [
            LessonTemplate(
                id: "gaming-recap",
                title: "游戏复盘表达",
                warmup: "回想一次你逆风翻盘的对局。",
                passage: "Our team lost two early rounds, but we adjusted our strategy and controlled the map. Once communication improved, we won three rounds in a row.",
                phrases: [
                    LessonPhrase(
                        english: "adjust strategy",
                        chinese: "调整策略",
                        example: "Good players adjust strategy quickly."
                    ),
                    LessonPhrase(
                        english: "in a row",
                        chinese: "连续地",
                        example: "She solved five problems in a row."
                    )
                ],
                question: "队伍翻盘的关键因素是什么？",
                options: [
                    "换了新设备",
                    "沟通改善并调整策略",
                    "对手提前退出"
                ],
                answerIndex: 1,
                explanation: "原文强调 strategy 调整与 communication 改善。"
            ),
            LessonTemplate(
                id: "gaming-caster",
                title: "直播解说表达",
                warmup: "尝试用英文描述一场精彩团战。",
                passage: "The final fight looked risky, but the support player timed the shield perfectly. That single move changed momentum and secured the victory.",
                phrases: [
                    LessonPhrase(
                        english: "change momentum",
                        chinese: "扭转局势",
                        example: "One smart decision can change momentum."
                    ),
                    LessonPhrase(
                        english: "secure the victory",
                        chinese: "锁定胜局",
                        example: "They secured the victory in overtime."
                    )
                ],
                question: "什么动作改变了比赛局势？",
                options: [
                    "辅助完美时机开盾",
                    "打野单独绕后",
                    "中路换线"
                ],
                answerIndex: 0,
                explanation: "timed the shield perfectly 是决定性动作。"
            )
        ],
        .music: [
            LessonTemplate(
                id: "music-share",
                title: "音乐分享表达",
                warmup: "给朋友推荐一首最近循环的歌。",
                passage: "I discovered this song on a rainy evening, and the rhythm instantly lifted my mood. The lyrics are simple, but the melody keeps playing in my head.",
                phrases: [
                    LessonPhrase(
                        english: "lift my mood",
                        chinese: "提振心情",
                        example: "A short walk can lift my mood."
                    ),
                    LessonPhrase(
                        english: "keeps playing in my head",
                        chinese: "一直在脑中循环",
                        example: "That chorus keeps playing in my head."
                    )
                ],
                question: "这首歌最打动作者的点是什么？",
                options: [
                    "歌词复杂",
                    "节奏提振情绪且旋律洗脑",
                    "演唱会现场灯光"
                ],
                answerIndex: 1,
                explanation: "关键词是 rhythm lifted my mood 和 melody keeps playing in my head。"
            ),
            LessonTemplate(
                id: "music-practice",
                title: "练琴反馈表达",
                warmup: "描述你一次有效的练习过程。",
                passage: "I practiced the same section slowly for twenty minutes. After repeating it with a metronome, my timing became stable and the whole piece sounded cleaner.",
                phrases: [
                    LessonPhrase(
                        english: "with a metronome",
                        chinese: "配合节拍器",
                        example: "Practicing with a metronome improves timing."
                    ),
                    LessonPhrase(
                        english: "sounded cleaner",
                        chinese: "听起来更干净",
                        example: "The second take sounded cleaner."
                    )
                ],
                question: "作者的演奏为何变好？",
                options: [
                    "换了更贵的乐器",
                    "放慢并重复练习，配合节拍器",
                    "只练了开头部分"
                ],
                answerIndex: 1,
                explanation: "slowly + repeating + metronome 直接带来 timing 稳定。"
            )
        ]
    ]
}

// MARK: - 待办清单

extension AppModel {
    /// Today's "YYYY-MM-DD" key, in the app calendar's timezone.
    private func todoTodayKey() -> String {
        todoDayKey(for: Date(), calendar: calendar)
    }

    /// Imports the legacy app's data once, runs daily carry-over, and loads the
    /// in-memory todo state. Called at startup.
    func loadTodoState() {
        guard let store = todoStore else { return }
        let today = todoTodayKey()
        do {
            _ = try store.importLegacyDataIfNeeded(today: today)
            todos = try store.runCarryOver(today: today)
            customTags = try store.loadCustomTags()
            templates = try store.loadTemplates()
            savedReports = try store.loadSavedReports()
            let memo = try store.loadMemo()
            todoMemo = memo.text
            todoMemoUpdatedAt = memo.updatedAt
        } catch {
            statusMessage = "待办数据加载失败：\(error.localizedDescription)"
        }
        rescheduleAllTodoReminders()
    }

    /// Re-runs carry-over if the day rolled over since the app was last active.
    func runTodoCarryOverIfNeeded() {
        guard let store = todoStore else { return }
        let today = todoTodayKey()
        if (try? store.loadLastOpenDate()) == today { return }
        todos = (try? store.runCarryOver(today: today)) ?? todos
    }

    func refreshTodos() {
        guard let store = todoStore else { return }
        todos = (try? store.fetchAll()) ?? todos
    }

    // MARK: Derived state

    var visibleTodoGroups: [TodoDateGroup] {
        TodoFilter.visibleGroups(
            todos: todos,
            category: todoFilterCategory,
            status: todoFilterStatus,
            search: todoSearchQuery,
            tag: todoFilterTag,
            sortByPriority: todoSortByPriority
        )
    }

    /// Open (non-archived, non-done) todos, soonest-due first.
    var openTodos: [TodoItem] {
        todos
            .filter { !$0.archived && $0.status != .done }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?) where l != r: return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.order < rhs.order
                }
            }
    }

    var openTodoCount: Int { openTodos.count }

    var todoStats: TodoStats {
        TodoStats.compute(todos: todos, today: todoTodayKey(), calendar: calendar)
    }

    // MARK: Mutations

    func addTodo(
        title: String,
        category: TodoCategory = .feature,
        priority: TodoPriority = .medium,
        dueDate: String? = nil,
        note: String? = nil,
        tags: [String]? = nil,
        bugCause: String? = nil,
        fixPlan: String? = nil
    ) {
        let trimmedTitle = title.trimmed
        guard !trimmedTitle.isEmpty else { return }
        let now = Date()
        let today = todoTodayKey()

        // Bump existing same-date todos down so the new one lands on top.
        var toPersist: [TodoItem] = []
        for todo in todos where todo.date == today && !todo.archived {
            var bumped = todo
            bumped.order += 1
            toPersist.append(bumped)
        }

        let item = TodoItem(
            id: UUID().uuidString,
            title: trimmedTitle,
            category: category,
            priority: priority,
            status: .pending,
            date: today,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            order: 0,
            archived: false,
            dueDate: dueDate,
            note: note?.trimmed.isEmpty == true ? nil : note,
            tags: tags,
            subtasks: nil,
            attachments: nil,
            changelog: nil,
            bugCause: bugCause,
            fixPlan: fixPlan,
            convertedToOptimizationId: nil
        )
        toPersist.append(item)

        persistTodos(toPersist)
        refreshTodos()
        syncTodoReminder(for: item)
        statusMessage = "已添加待办：\(trimmedTitle)"
    }

    /// Applies an edit, records changelog entries for tracked-field changes,
    /// enforces the "completedAt is set once, never cleared" rule, persists, and
    /// refreshes.
    func updateTodo(id: String, _ mutate: (inout TodoItem) -> Void) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let old = todos[index]
        var new = old
        mutate(&new)
        let now = Date()
        new.updatedAt = now

        var log = new.changelog ?? []
        func track(_ field: TrackedField, _ before: String?, _ after: String?) {
            guard before != after else { return }
            log.append(ChangeLogEntry(timestamp: now, field: field.rawValue, oldValue: before, newValue: after))
        }
        track(.title, old.title, new.title)
        track(.category, old.category.title, new.category.title)
        track(.priority, old.priority.title, new.priority.title)
        track(.status, old.status.chineseLabel, new.status.chineseLabel)
        track(.dueDate, old.dueDate, new.dueDate)
        track(.note, old.note, new.note)
        if log.count != (old.changelog?.count ?? 0) {
            new.changelog = log
        }

        // completedAt: set on first transition to done, never cleared.
        if new.status == .done && new.completedAt == nil {
            new.completedAt = now
        }

        persistTodo(new)
        refreshTodos()
        syncTodoReminder(for: new)
    }

    func toggleTodoStatus(id: String) {
        updateTodo(id: id) { $0.status = $0.status.next }
    }

    func deleteTodo(id: String) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        todoUndoWorkItem?.cancel()

        deletedTodo = todo
        do {
            try todoStore?.delete(id: id)
        } catch {
            statusMessage = "删除待办失败：\(error.localizedDescription)"
        }
        reminderScheduler.cancelTodoReminder(id: id)
        refreshTodos()

        // Auto-clear the undo affordance after the window passes.
        let work = DispatchWorkItem { [weak self] in
            self?.deletedTodo = nil
            self?.todoUndoWorkItem = nil
        }
        todoUndoWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    func undoDeleteTodo() {
        guard let todo = deletedTodo else { return }
        todoUndoWorkItem?.cancel()
        todoUndoWorkItem = nil
        persistTodo(todo)
        deletedTodo = nil
        refreshTodos()
    }

    func clearDeletedTodo() {
        todoUndoWorkItem?.cancel()
        todoUndoWorkItem = nil
        deletedTodo = nil
    }

    private func persistTodo(_ item: TodoItem) {
        guard let store = todoStore else { return }
        do {
            try store.upsert(item)
        } catch {
            statusMessage = "保存待办失败：\(error.localizedDescription)"
        }
    }

    private func persistTodos(_ items: [TodoItem]) {
        guard let store = todoStore, !items.isEmpty else { return }
        do {
            try store.upsertMany(items)
        } catch {
            statusMessage = "保存待办失败：\(error.localizedDescription)"
        }
    }

    // MARK: Desktop pet

    /// Add a todo submitted from the pet's in-bubble form, then confirm.
    func addTodoFromPet(_ draft: NewTodoDraft) {
        addTodo(
            title: draft.title,
            category: draft.category,
            priority: draft.priority,
            dueDate: draft.dueDate,
            note: draft.note
        )
        popoverController.presentFeedback(title: "已添加待办", message: draft.title)
    }

    /// Show today's open todos in an interactive pet bubble.
    func showDesktopTodos() {
        refreshTodos()
        let today = todoTodayKey()
        let open = openTodos
        guard !open.isEmpty else {
            popoverController.presentFeedback(title: "待办", message: "今天没有未完成的待办 🎉")
            return
        }
        let rows = open.prefix(4).map { todo in
            DesktopPetTodoRow(
                id: todo.id,
                title: todo.title,
                dueLabel: todoDueInfo(dueDate: todo.dueDate, today: today, calendar: calendar)?.text
            )
        }
        popoverController.presentTodoBubble(rows: Array(rows), openCount: open.count)
    }

    /// Mark a todo done from the pet bubble, then re-present so the next item
    /// surfaces (mirrors the daily-word advance flow).
    func completeTodoFromPet(id: String) {
        guard let todo = todos.first(where: { $0.id == id }) else {
            showDesktopTodos()
            return
        }
        let title = todo.title
        updateTodo(id: id) { $0.status = .done }
        popoverController.presentFeedback(
            title: "已完成",
            message: title,
            autoDismissAfter: DesktopPetBubbleTiming.dailyWordFeedbackAutoAdvanceSeconds
        ) { [weak self] in
            self?.showDesktopTodos()
        }
    }

    /// Open the main window focused on the 待办 tab (pet "打开列表").
    func openTodoListFromPet() {
        shouldFocusTodoTab = true
        openMainWindow()
    }

    // MARK: Subtasks

    func addSubtask(todoId: String, title: String) {
        let trimmed = title.trimmed
        guard !trimmed.isEmpty else { return }
        updateTodo(id: todoId) {
            $0.subtasks = ($0.subtasks ?? []) + [Subtask(id: UUID().uuidString, title: trimmed, done: false)]
        }
    }

    func toggleSubtask(todoId: String, subtaskId: String) {
        updateTodo(id: todoId) { item in
            if let index = item.subtasks?.firstIndex(where: { $0.id == subtaskId }) {
                item.subtasks?[index].done.toggle()
            }
        }
    }

    func removeSubtask(todoId: String, subtaskId: String) {
        updateTodo(id: todoId) { $0.subtasks?.removeAll { $0.id == subtaskId } }
    }

    // MARK: Archive

    func archiveTodo(id: String) {
        updateTodo(id: id) { $0.archived = true }
        reminderScheduler.cancelTodoReminder(id: id)
    }

    func unarchiveTodo(id: String) {
        updateTodo(id: id) { $0.archived = false }
    }

    func archiveDoneTodos() {
        let now = Date()
        var toPersist: [TodoItem] = []
        for todo in todos where todo.status == .done && !todo.archived {
            var archived = todo
            archived.archived = true
            archived.updatedAt = now
            toPersist.append(archived)
        }
        guard !toPersist.isEmpty else { return }
        persistTodos(toPersist)
        refreshTodos()
        statusMessage = "已归档 \(toPersist.count) 项已完成待办"
    }

    var archivedTodos: [TodoItem] {
        todos.filter(\.archived).sorted { $0.date > $1.date }
    }

    /// Convert a bug into a fresh optimization task and mark the bug done,
    /// linking them via `convertedToOptimizationId` (ported from the web app).
    func convertBugToOptimization(bugId: String) {
        guard let bug = todos.first(where: { $0.id == bugId }), bug.category == .bug else { return }
        let now = Date()
        let today = todoTodayKey()
        let optimizationId = UUID().uuidString

        var toPersist: [TodoItem] = []
        for todo in todos where todo.date == today && !todo.archived {
            var bumped = todo
            bumped.order += 1
            toPersist.append(bumped)
        }

        let optimizationNote = (bug.fixPlan?.isEmpty == false) ? "来源Bug修复方案: \(bug.fixPlan!)" : nil
        let optimization = TodoItem(
            id: optimizationId, title: "优化: \(bug.title)", category: .optimization,
            priority: bug.priority, status: .pending, date: today,
            createdAt: now, updatedAt: now, completedAt: nil, order: 0, archived: false,
            dueDate: nil, note: optimizationNote, tags: nil, subtasks: nil, attachments: nil,
            changelog: nil, bugCause: nil, fixPlan: nil, convertedToOptimizationId: nil
        )
        toPersist.append(optimization)

        var resolvedBug = bug
        resolvedBug.status = .done
        if resolvedBug.completedAt == nil { resolvedBug.completedAt = now }
        resolvedBug.convertedToOptimizationId = optimizationId
        resolvedBug.updatedAt = now
        toPersist.append(resolvedBug)

        persistTodos(toPersist)
        refreshTodos()
        reminderScheduler.cancelTodoReminder(id: bug.id)
        statusMessage = "已将 Bug 转为优化项"
    }

    // MARK: Reorder

    /// Move a todo one slot up/down within its date group (by `order`).
    func moveTodo(id: String, in dateGroup: String, up: Bool) {
        let group = todos
            .filter { $0.date == dateGroup && !$0.archived }
            .sorted { $0.order < $1.order }
        guard let index = group.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard group.indices.contains(target) else { return }
        var ids = group.map(\.id)
        ids.swapAt(index, target)
        reorderTodos(dateGroup: dateGroup, orderedIds: ids)
    }

    func reorderTodos(dateGroup: String, orderedIds: [String]) {
        let now = Date()
        var toPersist: [TodoItem] = []
        for (index, id) in orderedIds.enumerated() {
            if let position = todos.firstIndex(where: { $0.id == id && $0.date == dateGroup }) {
                var todo = todos[position]
                if todo.order != index {
                    todo.order = index
                    todo.updatedAt = now
                    toPersist.append(todo)
                }
            }
        }
        guard !toPersist.isEmpty else { return }
        persistTodos(toPersist)
        refreshTodos()
    }

    // MARK: Tags

    func addCustomTag(_ name: String) {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty, !customTags.contains(trimmed) else { return }
        customTags.append(trimmed)
        try? todoStore?.saveCustomTags(customTags)
    }

    func removeCustomTag(_ name: String) {
        customTags.removeAll { $0 == name }
        try? todoStore?.saveCustomTags(customTags)
    }

    func setTags(todoId: String, tags: [String]) {
        let cleaned = tags.map { $0.trimmed }.filter { !$0.isEmpty }
        updateTodo(id: todoId) { $0.tags = cleaned.isEmpty ? nil : cleaned }
        for tag in cleaned where !customTags.contains(tag) {
            addCustomTag(tag)
        }
    }

    // MARK: Templates

    func addTemplate(
        name: String,
        category: TodoCategory,
        priority: TodoPriority,
        tags: [String],
        subtasks: [String],
        note: String
    ) {
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else { return }
        let template = TodoTemplate(
            id: UUID().uuidString,
            name: trimmedName,
            category: category,
            priority: priority,
            tags: tags.isEmpty ? nil : tags,
            subtasks: subtasks.isEmpty ? nil : subtasks,
            note: note.trimmed.isEmpty ? nil : note
        )
        templates.append(template)
        try? todoStore?.saveTemplates(templates)
    }

    func deleteTemplate(id: String) {
        templates.removeAll { $0.id == id }
        try? todoStore?.saveTemplates(templates)
    }

    func createTodoFromTemplate(id: String) {
        guard let template = templates.first(where: { $0.id == id }) else { return }
        let now = Date()
        let today = todoTodayKey()

        var toPersist: [TodoItem] = []
        for todo in todos where todo.date == today && !todo.archived {
            var bumped = todo
            bumped.order += 1
            toPersist.append(bumped)
        }
        let item = makeTodoFromTemplate(template, date: today, now: now)
        toPersist.append(item)

        persistTodos(toPersist)
        refreshTodos()
        statusMessage = "已从模板创建：\(template.name)"
    }

    // MARK: Memo

    func setTodoMemo(_ text: String) {
        todoMemo = text
        let now = Date()
        todoMemoUpdatedAt = now
        todoMemoSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? self.todoStore?.saveMemo(self.todoMemo, updatedAt: now)
            self.todoMemoSaveWork = nil
        }
        todoMemoSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: Weekly report

    func weeklyReport(offset: Int) -> WeeklyReport {
        WeeklyReport.generate(todos: todos, offset: offset, calendar: calendar)
    }

    /// Persist a user-edited report, keyed by the week-start "MM/dd".
    func saveWeeklyReport(weekStart: String, text: String) {
        savedReports[weekStart] = text
        try? todoStore?.saveSavedReports(savedReports)
        statusMessage = "已保存周报 \(weekStart)"
    }

    func clearSavedReport(weekStart: String) {
        savedReports[weekStart] = nil
        try? todoStore?.saveSavedReports(savedReports)
    }

    // MARK: Reminders

    /// Schedule or cancel the due reminder for one todo, based on its state.
    private func syncTodoReminder(for todo: TodoItem) {
        guard let due = todo.dueDate, !due.isEmpty, todo.status != .done, !todo.archived else {
            reminderScheduler.cancelTodoReminder(id: todo.id)
            return
        }
        Task {
            if await reminderScheduler.requestAuthorizationIfNeeded() {
                reminderScheduler.scheduleTodoReminder(id: todo.id, title: todo.title, dueDateKey: due)
            }
        }
    }

    /// Re-arm reminders for all open, future-dated todos plus the weekly-report
    /// nudge (covers app restarts). Skips entirely when there are no todos so a
    /// fresh user isn't prompted for notification permission unnecessarily.
    func rescheduleAllTodoReminders() {
        guard !todos.isEmpty else { return }
        let due = todos.filter { !$0.archived && $0.status != .done && ($0.dueDate?.isEmpty == false) }
        Task {
            guard await reminderScheduler.requestAuthorizationIfNeeded() else { return }
            reminderScheduler.scheduleWeeklyReportReminder()
            for todo in due {
                if let key = todo.dueDate {
                    reminderScheduler.scheduleTodoReminder(id: todo.id, title: todo.title, dueDateKey: key)
                }
            }
        }
    }
}
