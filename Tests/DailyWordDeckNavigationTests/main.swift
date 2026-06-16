func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

expectEqual(
    DailyWordDeckNavigation.nextIndex(after: 0, cardCount: 3),
    1,
    "deferring the first word should show the next word"
)
expectEqual(
    DailyWordDeckNavigation.nextIndex(after: 2, cardCount: 3),
    0,
    "deferring the last word should keep it in rotation and wrap to the first word"
)
expectEqual(
    DailyWordDeckNavigation.nextIndex(after: 0, cardCount: 1),
    0,
    "deferring a single remaining word should keep showing that word"
)
expectEqual(
    DailyWordDeckNavigation.nextIndex(after: 5, cardCount: 0),
    0,
    "empty decks should normalize to index zero"
)
expectEqual(
    DailyWordDeckNavigation.nextIndex(after: 9, cardCount: 3),
    1,
    "out-of-range indexes should normalize before advancing"
)

print("DailyWordDeckNavigationTests passed")
