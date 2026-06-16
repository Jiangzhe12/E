enum DailyWordDeckNavigation {
    static func nextIndex(after currentIndex: Int, cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        let normalizedIndex = ((currentIndex % cardCount) + cardCount) % cardCount
        return (normalizedIndex + 1) % cardCount
    }
}
