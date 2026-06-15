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
    dailyQuota: 3,
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

print("WordCarouselStoreTests passed")
