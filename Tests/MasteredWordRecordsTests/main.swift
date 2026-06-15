import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let suiteName = "EnglishCoach.MasteredWordRecordsTests.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suiteName) else {
    fatalError("failed to create isolated defaults suite")
}
defer {
    defaults.removePersistentDomain(forName: suiteName)
}

var currentDate = Date(timeIntervalSince1970: 1_718_582_400)
let store = WordCarouselStore(
    defaults: defaults,
    coreWords: ["alpha", "bravo", "charlie", "delta"],
    extendedWords: [],
    dailyQuota: 4,
    dateProvider: { currentDate },
    calendar: Calendar(identifier: .gregorian),
    stateKey: "mastered.records.test"
)

let firstDeck = store.snapshot().todayWords
store.markMastered(word: firstDeck[0])
currentDate = currentDate.addingTimeInterval(60 * 60)
store.markMastered(word: firstDeck[1])

let records = store.snapshot().masteredRecords
expect(records.count == 2, "snapshot should expose mastered record details")
expect(records[0].masteredAt > records[1].masteredAt, "records should be newest first")
expect(records[0].word == firstDeck[1], "newest mastered word should be first")

print("MasteredWordRecordsTests passed")
