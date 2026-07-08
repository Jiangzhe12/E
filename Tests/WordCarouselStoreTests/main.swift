import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let suiteName = "EnglishCoach.WordCarouselStoreTests.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suiteName) else {
    fatalError("failed to create isolated defaults suite")
}
defer {
    defaults.removePersistentDomain(forName: suiteName)
}

let fixedDate = Date(timeIntervalSince1970: 1_718_582_400) // 2024-06-17 UTC
let words = (1...8).map { "word\($0)" }
let store = WordCarouselStore(
    defaults: defaults,
    coreWords: words,
    extendedWords: [],
    dailyBudgetProvider: { 3 },
    newWordGroupStep: 3,
    dateProvider: { fixedDate },
    calendar: Calendar(identifier: .gregorian),
    stateKey: "test.state"
)

let firstSnapshot = store.snapshot()
expect(firstSnapshot.todayWords.count == 3, "initial daily deck should fill to the quota")
let firstWord = firstSnapshot.todayWords[0]

store.markMastered(word: firstWord)
let afterMastery = store.snapshot()

expect(!afterMastery.todayWords.contains(firstWord), "mastered word should be removed from today's deck")
expect(afterMastery.todayWords.count == 2, "same-day deck should shrink instead of refilling after mastery")
expect(afterMastery.todayMasteredCount == 1, "mastered count should track today's completed new words")
expect(afterMastery.dailyTarget == 3, "daily target should start at the configured quota")

for word in afterMastery.todayWords {
    store.markMastered(word: word)
}

let completed = store.snapshot()
expect(completed.todayMasteredCount == 3, "all three words should count toward today's target")
expect(completed.todayWords.isEmpty, "completed daily target should not keep presenting word cards")
expect(completed.hasCompletedDailyTarget, "snapshot should expose completed daily target state")

store.expandTodayTarget()
let expanded = store.snapshot()
expect(expanded.dailyTarget == 6, "starting the next group should add one more quota to today's target")
expect(!expanded.hasCompletedDailyTarget, "expanded target should reopen daily learning")
expect(expanded.todayWords.count == 3, "expanded target should fill the next group")

let reinforcementSuiteName = "EnglishCoach.WordCarouselStoreTests.reinforcement.\(UUID().uuidString)"
guard let reinforcementDefaults = UserDefaults(suiteName: reinforcementSuiteName) else {
    fatalError("failed to create isolated reinforcement defaults suite")
}
defer {
    reinforcementDefaults.removePersistentDomain(forName: reinforcementSuiteName)
}

var reinforcementDate = fixedDate
let reinforcementStore = WordCarouselStore(
    defaults: reinforcementDefaults,
    coreWords: words,
    extendedWords: [],
    dailyBudgetProvider: { 3 },
    newWordGroupStep: 3,
    dateProvider: { reinforcementDate },
    calendar: Calendar(identifier: .gregorian),
    stateKey: "reinforcement.state"
)
let reinforcementInitial = reinforcementStore.snapshot()
let unfamiliarWord = reinforcementInitial.todayWords[0]

reinforcementStore.markNeedsPractice(word: unfamiliarWord)
let afterUnfamiliar = reinforcementStore.snapshot()

expect(!afterUnfamiliar.todayWords.contains(unfamiliarWord), "unfamiliar word should leave today's active deck")
expect(afterUnfamiliar.todayMasteredCount == 1, "unfamiliar word should count as completed for today's quota")
expect(!afterUnfamiliar.masteredWords.contains(unfamiliarWord), "unfamiliar word should not be treated as mastered")
expect(!afterUnfamiliar.masteredRecords.contains { $0.word == unfamiliarWord }, "unfamiliar word should not appear in mastered records")
expect(afterUnfamiliar.totalMasteredCount == 0, "unfamiliar word should not increase total mastered count")

reinforcementDate = reinforcementDate.addingTimeInterval(86_400)
let tomorrowReinforcement = reinforcementStore.snapshot()
expect(tomorrowReinforcement.reviewDueWords.contains(unfamiliarWord), "unfamiliar word should come back for focused review later")
expect(!tomorrowReinforcement.todayWords.contains(unfamiliarWord), "unfamiliar word should not be redrawn as a fresh word before review")

// MARK: - Daily budget: review cap + backlog drain

func makeStore(
    suffix: String,
    budget: Int,
    coreCount: Int,
    studyDays: Set<Int> = Set(1...7),
    date: @escaping () -> Date
) -> (WordCarouselStore, UserDefaults, String) {
    let name = "EnglishCoach.WordCarouselStoreTests.\(suffix).\(UUID().uuidString)"
    guard let d = UserDefaults(suiteName: name) else { fatalError("no defaults suite") }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let s = WordCarouselStore(
        defaults: d,
        coreWords: (1...coreCount).map { "w\($0)" },
        extendedWords: [],
        dailyBudgetProvider: { budget },
        newWordGroupStep: budget,
        studyDaysProvider: { studyDays },
        dateProvider: date,
        calendar: cal,
        stateKey: "\(suffix).state"
    )
    return (s, d, name)
}

// day0 = 2024-06-17 (Monday) 00:00 UTC.
let day0 = Date(timeIntervalSince1970: 1_718_582_400)

do {
    var now = day0
    let (store, defaults, name) = makeStore(suffix: "cap", budget: 5, coreCount: 20, date: { now })
    defer { defaults.removePersistentDomain(forName: name) }

    _ = store.snapshot() // seed day 0
    for i in 1...8 { store.markMastered(word: "w\(i)") } // 8 reviews all due day 1

    now = day0.addingTimeInterval(86_400) // day 1 (rollover)
    let s1 = store.snapshot()
    expect(s1.reviewDueWords.count == 5, "reviews are capped at the daily budget")
    expect(s1.reviewBacklogCount == 3, "reviews beyond the cap become backlog")
    expect(s1.todayWords.isEmpty, "no new words when reviews fill the whole budget")

    // Same-day recompute must produce the same cap (covers the post-update
    // migration path where dayKey already == today and there's no rollover).
    let s1Again = store.snapshot()
    expect(s1Again.reviewDueWords.count == 5 && s1Again.reviewBacklogCount == 3,
           "the cap holds on a same-day recompute, not just at rollover")

    // Answer the day's 5 shown reviews; the held-back 3 must not resurface today.
    for w in s1.reviewDueWords { store.advanceReview(word: w) }
    let s1After = store.snapshot()
    expect(s1After.reviewDueWords.isEmpty, "no more reviews surface after the day's cap is spent")
    expect(s1After.reviewBacklogCount == 3, "the 3 held-back reviews wait for the next day")

    // Next day, the remaining backlog drains (and stays under the cap).
    now = day0.addingTimeInterval(2 * 86_400) // day 2
    let s2 = store.snapshot()
    expect(s2.reviewDueWords.count == 3, "the remaining backlog surfaces the next day")
    expect(s2.reviewBacklogCount == 0, "backlog is cleared once it fits under the cap")
}

// MARK: - New words fill the budget left after reviews

do {
    var now = day0
    let (store, defaults, name) = makeStore(suffix: "fill", budget: 10, coreCount: 30, date: { now })
    defer { defaults.removePersistentDomain(forName: name) }

    _ = store.snapshot()
    for i in 1...4 { store.markMastered(word: "w\(i)") } // 4 reviews due day 1

    now = day0.addingTimeInterval(86_400)
    let s = store.snapshot()
    expect(s.reviewDueWords.count == 4, "all 4 reviews fit under the budget")
    expect(s.todayWords.count == 6, "new words fill the remaining budget (10 - 4)")
}

// MARK: - Rest day: no new words, target 0, still surfaces reviews

do {
    // day0 + 5 days = 2024-06-22 (Saturday, weekday 7) → a rest day.
    let saturday = day0.addingTimeInterval(5 * 86_400)
    let (store, defaults, name) = makeStore(
        suffix: "rest", budget: 10, coreCount: 20, studyDays: [2, 3, 4, 5], date: { saturday }
    )
    defer { defaults.removePersistentDomain(forName: name) }

    let s = store.snapshot()
    expect(s.isRestDay, "Saturday is a rest day under a Mon–Thu schedule")
    expect(s.todayWords.isEmpty, "rest days introduce no new words")
    expect(s.dailyTarget == 0, "rest-day new-word target is 0")

    // "想学也可以": opening a group must survive the next rest-day snapshot.
    store.expandTodayTarget()
    let opened = store.snapshot()
    expect(opened.dailyTarget == 10, "opening a group on a rest day raises the target")
    expect(!opened.todayWords.isEmpty, "opening a group on a rest day yields new words")
}

// MARK: - Roll-forward: reviews scheduled onto a rest day move to the next study day

do {
    // day0 + 3 days = 2024-06-20 (Thursday, weekday 5) — a study day.
    let thursday = day0.addingTimeInterval(3 * 86_400)
    let (store, defaults, name) = makeStore(
        suffix: "roll", budget: 10, coreCount: 20, studyDays: [2, 3, 4, 5], date: { thursday }
    )
    defer { defaults.removePersistentDomain(forName: name) }

    _ = store.snapshot()
    store.markMastered(word: "w1") // first review would be Friday → roll to Monday
    guard let record = store.snapshot().masteredRecords.first(where: { $0.word == "w1" }) else {
        fatalError("expected a mastered record for w1")
    }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    expect(cal.component(.weekday, from: record.nextReviewDue) == 2,
           "a review landing on Friday rolls forward to Monday (weekday 2)")
}

// MARK: - Day-granular due: a word due later today counts as due today

do {
    let day0Noon = day0.addingTimeInterval(12 * 3_600)
    var now = day0Noon
    let (store, defaults, name) = makeStore(suffix: "grain", budget: 10, coreCount: 20, date: { now })
    defer { defaults.removePersistentDomain(forName: name) }

    _ = store.snapshot()
    store.markMastered(word: "w1") // nextReviewDue = day1 at noon

    now = day0.addingTimeInterval(86_400 + 60) // day 1 at 00:01, earlier clock than noon
    let s = store.snapshot()
    expect(s.reviewDueWords.contains("w1"),
           "a word due later today is treated as due today (day-granular comparison)")
}

print("WordCarouselStoreTests passed")
