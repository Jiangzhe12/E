import Foundation

struct WordCarouselSnapshot {
    let dayKey: String
    let todayWords: [String]
    let reviewDueWords: [String]
    let masteredWords: Set<String>
    let masteredRecords: [MasteredWordRecord]
    let dailyTarget: Int
    let hasCompletedDailyTarget: Bool
    let todayMasteredCount: Int
    let totalMasteredCount: Int
    let graduatedWords: Set<String>
}

struct MasteredWordRecord: Identifiable {
    var id: String { word }
    let word: String
    let masteredAt: Date
    let reviewStage: Int
    let nextReviewDue: Date
    let isGraduated: Bool
}

/// Spaced-repetition scheduling intervals, in days, for stages 0 through 4.
/// Stage 5 = graduated (won't come back for review).
private let srsIntervalDays: [Int] = [1, 3, 7, 14, 30]

/// Result of trying to add a looked-up word to the learning deck.
enum AddToLearningOutcome {
    case added
    case alreadyLearning
    case alreadyMastered
}

final class WordCarouselStore {
    /// Stored per-word state for the SRS scheduler.
    ///
    /// Old persisted records (before SRS) only had `word` and `masteredAt` —
    /// the custom `init(from:)` gives those sensible defaults (treat as
    /// graduated so we don't surprise users with a flood of reviews).
    private struct MasteryRecord: Codable {
        let word: String
        let masteredAt: Date
        var reviewStage: Int
        var nextReviewDue: Date

        init(
            word: String,
            masteredAt: Date,
            reviewStage: Int = 0,
            nextReviewDue: Date
        ) {
            self.word = word
            self.masteredAt = masteredAt
            self.reviewStage = reviewStage
            self.nextReviewDue = nextReviewDue
        }

        enum CodingKeys: String, CodingKey {
            case word
            case masteredAt
            case reviewStage
            case nextReviewDue
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.word = try c.decode(String.self, forKey: .word)
            self.masteredAt = try c.decode(Date.self, forKey: .masteredAt)
            // Missing fields = pre-SRS record: treat as already graduated
            // (stage 5, review so far in the future that it never comes back).
            self.reviewStage = try c.decodeIfPresent(Int.self, forKey: .reviewStage) ?? 5
            self.nextReviewDue = try c.decodeIfPresent(Date.self, forKey: .nextReviewDue) ?? .distantFuture
        }

        var isGraduated: Bool { reviewStage >= srsIntervalDays.count }
    }

    private struct PersistedState: Codable {
        var dayKey: String
        var todayWords: [String]
        var masteredWords: [String]
        var masteryRecords: [MasteryRecord]
        var dailyTarget: Int
        /// Words the user explicitly added from a lookup. They stay in the
        /// daily deck (beyond the normal quota) until mastered.
        var customWords: [String]

        init(
            dayKey: String,
            todayWords: [String],
            masteredWords: [String],
            masteryRecords: [MasteryRecord],
            dailyTarget: Int,
            customWords: [String] = []
        ) {
            self.dayKey = dayKey
            self.todayWords = todayWords
            self.masteredWords = masteredWords
            self.masteryRecords = masteryRecords
            self.dailyTarget = dailyTarget
            self.customWords = customWords
        }

        enum CodingKeys: String, CodingKey {
            case dayKey
            case todayWords
            case masteredWords
            case masteryRecords
            case dailyTarget
            case customWords
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dayKey = try c.decode(String.self, forKey: .dayKey)
            todayWords = try c.decode([String].self, forKey: .todayWords)
            masteredWords = try c.decode([String].self, forKey: .masteredWords)
            masteryRecords = try c.decode([MasteryRecord].self, forKey: .masteryRecords)
            dailyTarget = try c.decodeIfPresent(Int.self, forKey: .dailyTarget) ?? 0
            // Pre-customWords states won't have this key.
            customWords = try c.decodeIfPresent([String].self, forKey: .customWords) ?? []
        }
    }

    private let defaults: UserDefaults
    private let coreWords: [String]
    private let extendedWords: [String]
    private let dailyQuota: Int
    private let dateProvider: () -> Date
    private let calendar: Calendar
    private let stateKey: String

    init(
        defaults: UserDefaults,
        coreWords: [String],
        extendedWords: [String],
        dailyQuota: Int = 20,
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        stateKey: String = "wordCarousel.state.v1"
    ) {
        self.defaults = defaults
        self.coreWords = Self.uniqueWords(from: coreWords)
        self.extendedWords = Self.uniqueWords(from: extendedWords)
        self.dailyQuota = max(1, dailyQuota)
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.stateKey = stateKey
    }

    func snapshot() -> WordCarouselSnapshot {
        var state = loadState()
        let now = dateProvider()
        let todayKey = dayKey(for: now)
        let masteredSet = Set(state.masteredWords)
        let unavailableWords = unavailableWords(in: state)

        if state.dayKey != todayKey {
            state.dayKey = todayKey
            state.dailyTarget = dailyQuota
            state.todayWords = buildDailyWords(
                dayKey: todayKey,
                unavailableWords: unavailableWords
            )
        } else {
            state.dailyTarget = max(dailyQuota, state.dailyTarget)
            state.todayWords = state.todayWords.filter { !unavailableWords.contains($0) }
            normalizeTodayWords(state: &state)
        }

        if state.masteryRecords.count > 5000 {
            state.masteryRecords.removeFirst(state.masteryRecords.count - 5000)
        }

        persistState(state)

        let todayMasteredCount = self.todayMasteredCount(in: state, now: now)
        let hasCompletedDailyTarget = todayMasteredCount >= state.dailyTarget

        // User-added words ride along at the front of the deck, additively and
        // regardless of the daily quota. They are kept out of the persisted
        // `todayWords` (which stays bank-only so the quota refill stays sane)
        // and merged into the returned deck here.
        let pendingCustom = state.customWords.filter { !unavailableWords.contains($0) }
        var deckSeen = Set(state.todayWords)
        var customPrefix: [String] = []
        for word in pendingCustom where deckSeen.insert(word).inserted {
            customPrefix.append(word)
        }
        let combinedTodayWords = hasCompletedDailyTarget ? [] : customPrefix + state.todayWords

        // Words whose next-review date is <= now and haven't graduated yet.
        let reviewDueWords: [String] = state.masteryRecords
            .filter { !$0.isGraduated && $0.nextReviewDue <= now }
            .sorted { $0.nextReviewDue < $1.nextReviewDue }
            .map { $0.word }

        let graduatedWords: Set<String> = Set(
            state.masteryRecords.filter { $0.isGraduated }.map { $0.word }
        )

        return WordCarouselSnapshot(
            dayKey: state.dayKey,
            todayWords: combinedTodayWords,
            reviewDueWords: reviewDueWords,
            masteredWords: Set(state.masteredWords),
            masteredRecords: state.masteryRecords
                .filter { masteredSet.contains($0.word) }
                .map { record in
                    MasteredWordRecord(
                        word: record.word,
                        masteredAt: record.masteredAt,
                        reviewStage: record.reviewStage,
                        nextReviewDue: record.nextReviewDue,
                        isGraduated: record.isGraduated
                    )
                }
                .sorted { first, second in
                    if first.masteredAt == second.masteredAt {
                        return first.word < second.word
                    }
                    return first.masteredAt > second.masteredAt
                },
            dailyTarget: state.dailyTarget,
            hasCompletedDailyTarget: hasCompletedDailyTarget,
            todayMasteredCount: todayMasteredCount,
            totalMasteredCount: state.masteredWords.count,
            graduatedWords: graduatedWords
        )
    }

    /// Dates at which words were newly marked mastered. Used by the activity
    /// heatmap to count "new mastered word" events per day.
    func masteryDates() -> [Date] {
        loadState().masteryRecords.map { $0.masteredAt }
    }

    func markMastered(word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }

        var state = loadState()
        var masteredSet = Set(state.masteredWords)
        guard !masteredSet.contains(normalized) else { return }

        masteredSet.insert(normalized)
        state.masteredWords = Array(masteredSet).sorted()
        let now = dateProvider()
        let firstReviewDue = calendar.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(86_400)
        upsertMasteryRecord(
            &state,
            word: normalized,
            masteredAt: now,
            reviewStage: 0,
            nextReviewDue: firstReviewDue
        )

        let todayKey = dayKey(for: now)
        if state.dayKey != todayKey {
            state.dayKey = todayKey
            state.dailyTarget = dailyQuota
            state.todayWords = buildDailyWords(dayKey: todayKey, unavailableWords: unavailableWords(in: state))
        } else {
            state.todayWords.removeAll { $0 == normalized }
            state.customWords.removeAll { $0 == normalized }
            normalizeTodayWords(state: &state)
        }

        persistState(state)
    }

    /// User saw the word today but marked it as unfamiliar. It counts toward
    /// today's learning quota and leaves today's deck, but does not enter the
    /// mastered-word set. The SRS record brings it back for focused practice.
    func markNeedsPractice(word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }

        var state = loadState()
        let now = dateProvider()
        let firstReviewDue = calendar.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(86_400)

        upsertMasteryRecord(
            &state,
            word: normalized,
            masteredAt: now,
            reviewStage: 0,
            nextReviewDue: firstReviewDue
        )

        let todayKey = dayKey(for: now)
        if state.dayKey != todayKey {
            state.dayKey = todayKey
            state.dailyTarget = dailyQuota
            state.todayWords = buildDailyWords(dayKey: todayKey, unavailableWords: unavailableWords(in: state))
        } else {
            state.todayWords.removeAll { $0 == normalized }
            state.customWords.removeAll { $0 == normalized }
            normalizeTodayWords(state: &state)
        }

        persistState(state)
    }

    func unmarkMastered(word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }

        var state = loadState()
        var masteredSet = Set(state.masteredWords)
        guard masteredSet.contains(normalized) else { return }

        masteredSet.remove(normalized)
        state.masteredWords = Array(masteredSet).sorted()
        state.masteryRecords.removeAll { $0.word == normalized }

        let todayKey = dayKey(for: dateProvider())
        if state.dayKey != todayKey {
            state.dayKey = todayKey
            state.dailyTarget = dailyQuota
            state.todayWords = buildDailyWords(dayKey: todayKey, unavailableWords: unavailableWords(in: state))
        } else {
            normalizeTodayWords(state: &state)
        }

        persistState(state)
    }

    func expandTodayTarget() {
        var state = loadState()
        let now = dateProvider()
        let todayKey = dayKey(for: now)

        if state.dayKey != todayKey {
            state.dayKey = todayKey
            state.dailyTarget = dailyQuota
            state.todayWords = buildDailyWords(dayKey: todayKey, unavailableWords: unavailableWords(in: state))
        }

        state.dailyTarget = max(dailyQuota, state.dailyTarget) + dailyQuota
        let unavailableWords = unavailableWords(in: state)
        state.todayWords.removeAll { unavailableWords.contains($0) }
        fillTodayWordsIfNeeded(state: &state, dayKey: todayKey, unavailableWords: unavailableWords)

        persistState(state)
    }

    /// Add a looked-up word to the learning deck. It joins `customWords` and is
    /// injected at the front of today's deck so it shows up immediately, then
    /// follows the normal mastery + SRS lifecycle.
    @discardableResult
    func addToLearning(word: String) -> AddToLearningOutcome {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return .alreadyLearning }

        var state = loadState()
        if Set(state.masteredWords).contains(normalized) {
            return .alreadyMastered
        }
        if state.masteryRecords.contains(where: { $0.word == normalized }) {
            return .alreadyLearning
        }

        let alreadyTracked = state.customWords.contains(normalized)
            || state.todayWords.contains(normalized)

        if !state.customWords.contains(normalized) {
            state.customWords.append(normalized)
            persistState(state)
        }

        return alreadyTracked ? .alreadyLearning : .added
    }

    /// User reported "still remember" on a review word. Bump it to the next
    /// SRS stage and push `nextReviewDue` further out; if the new stage runs
    /// past the schedule, the word graduates and never comes back.
    func advanceReview(word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }

        var state = loadState()
        guard let index = state.masteryRecords.firstIndex(where: { $0.word == normalized }) else {
            return
        }

        let now = dateProvider()
        var record = state.masteryRecords[index]
        let newStage = record.reviewStage + 1
        record.reviewStage = newStage
        if newStage < srsIntervalDays.count {
            let days = srsIntervalDays[newStage]
            record.nextReviewDue = calendar.date(byAdding: .day, value: days, to: now)
                ?? now.addingTimeInterval(TimeInterval(days) * 86_400)
        } else {
            record.nextReviewDue = .distantFuture
        }
        state.masteryRecords[index] = record
        persistState(state)
    }

    /// User reported "forgot" on a review word. Reset the SRS stage to 0 and
    /// schedule it for tomorrow. Keep the word in `masteredWords` so it
    /// doesn't get re-drawn as a brand-new word in tomorrow's batch.
    func resetReview(word: String) {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return }

        var state = loadState()
        guard let index = state.masteryRecords.firstIndex(where: { $0.word == normalized }) else {
            return
        }

        let now = dateProvider()
        var record = state.masteryRecords[index]
        record.reviewStage = 0
        record.nextReviewDue = calendar.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(86_400)
        state.masteryRecords[index] = record
        persistState(state)
    }

    /// How many days until the word is next scheduled for review.
    /// Returns nil if the word is not in the mastery store, or has graduated.
    func daysUntilNextReview(for word: String) -> Int? {
        let normalized = Self.normalize(word)
        guard !normalized.isEmpty else { return nil }
        let state = loadState()
        guard let record = state.masteryRecords.first(where: { $0.word == normalized }),
              !record.isGraduated else {
            return nil
        }
        let now = dateProvider()
        let components = calendar.dateComponents([.day], from: now, to: record.nextReviewDue)
        return components.day
    }

    private func normalizeTodayWords(state: inout PersistedState) {
        // Always deduplicate first, regardless of current count. Persisted state
        // could have picked up duplicates from older builds or race conditions.
        var seen: Set<String> = []
        var ordered: [String] = []
        ordered.reserveCapacity(state.todayWords.count)
        for word in state.todayWords where seen.insert(word).inserted {
            ordered.append(word)
        }
        state.todayWords = Array(ordered.prefix(dailyQuota))
    }

    private func fillTodayWordsIfNeeded(
        state: inout PersistedState,
        dayKey: String,
        unavailableWords: Set<String>
    ) {
        normalizeTodayWords(state: &state)

        let remainingTarget = max(0, state.dailyTarget - todayMasteredCount(in: state, now: dateProvider()))
        let desiredActiveCount = min(dailyQuota, remainingTarget)
        guard state.todayWords.count < desiredActiveCount else { return }

        var seen = Set(state.todayWords)
        let candidateWords = candidatePool(unavailableWords: unavailableWords)
        let candidates = deterministicSelection(
            from: candidateWords,
            dayKey: "\(dayKey)-\(state.dailyTarget)",
            limit: candidateWords.count
        )

        for word in candidates {
            guard state.todayWords.count < desiredActiveCount else { break }
            if seen.insert(word).inserted {
                state.todayWords.append(word)
            }
        }
    }

    private func buildDailyWords(dayKey: String, unavailableWords: Set<String>) -> [String] {
        let candidates = candidatePool(unavailableWords: unavailableWords)
        guard !candidates.isEmpty else { return [] }
        return deterministicSelection(from: candidates, dayKey: dayKey, limit: min(dailyQuota, candidates.count))
    }

    private func candidatePool(unavailableWords: Set<String>) -> [String] {
        let coreAvailable = coreWords.filter { !unavailableWords.contains($0) }
        let extendedAvailable = extendedWords.filter { !unavailableWords.contains($0) && !coreWords.contains($0) }

        if coreAvailable.count >= dailyQuota {
            return coreAvailable
        }

        return coreAvailable + extendedAvailable
    }

    private func unavailableWords(in state: PersistedState) -> Set<String> {
        Set(state.masteredWords).union(state.masteryRecords.map(\.word))
    }

    private func upsertMasteryRecord(
        _ state: inout PersistedState,
        word: String,
        masteredAt: Date,
        reviewStage: Int,
        nextReviewDue: Date
    ) {
        if let index = state.masteryRecords.firstIndex(where: { $0.word == word }) {
            state.masteryRecords[index] = MasteryRecord(
                word: word,
                masteredAt: masteredAt,
                reviewStage: reviewStage,
                nextReviewDue: nextReviewDue
            )
        } else {
            state.masteryRecords.append(
                MasteryRecord(
                    word: word,
                    masteredAt: masteredAt,
                    reviewStage: reviewStage,
                    nextReviewDue: nextReviewDue
                )
            )
        }
    }

    private func deterministicSelection(from words: [String], dayKey: String, limit: Int) -> [String] {
        guard !words.isEmpty else { return [] }

        let seed = dayKey.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 131 &+ Int(scalar.value)) & 0x7fffffff
        }

        let count = words.count
        var selected: [String] = []
        selected.reserveCapacity(limit)

        let start = seed % count
        for offset in 0 ..< limit {
            let index = (start + offset) % count
            selected.append(words[index])
        }

        return selected
    }

    private func loadState() -> PersistedState {
        guard let data = defaults.data(forKey: stateKey),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState(
                dayKey: "",
                todayWords: [],
                masteredWords: [],
                masteryRecords: [],
                dailyTarget: dailyQuota
            )
        }

        return PersistedState(
            dayKey: decoded.dayKey,
            todayWords: Self.uniqueWords(from: decoded.todayWords),
            masteredWords: Self.uniqueWords(from: decoded.masteredWords),
            masteryRecords: decoded.masteryRecords,
            dailyTarget: max(dailyQuota, decoded.dailyTarget),
            customWords: Self.uniqueWords(from: decoded.customWords)
        )
    }

    private func todayMasteredCount(in state: PersistedState, now: Date) -> Int {
        state.masteryRecords.filter {
            calendar.isDate($0.masteredAt, inSameDayAs: now)
        }.count
    }

    private func persistState(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func uniqueWords(from words: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        result.reserveCapacity(words.count)

        for word in words {
            let normalized = normalize(word)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }

    private static func normalize(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

}
