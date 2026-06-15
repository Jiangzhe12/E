func expectEqual(_ actual: String, _ expected: String, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

expectEqual(
    DailyWordProgress.statusText(masteredToday: 0, quota: 20, hasAvailableCard: true),
    "今日单词 1/20",
    "first daily word should start at 1/20"
)
expectEqual(
    DailyWordProgress.statusText(masteredToday: 1, quota: 20, hasAvailableCard: true),
    "今日单词 2/20",
    "next daily word should advance to 2/20 after one mastered word"
)
expectEqual(
    DailyWordProgress.statusText(masteredToday: 20, quota: 20, hasAvailableCard: false),
    "今日已完成",
    "completed daily quota should show completion"
)
expectEqual(
    DailyWordProgress.bubbleBadgeText(masteredToday: 1, quota: 20, isReview: false),
    "2/20",
    "daily word bubble should show the next progress number"
)
expectEqual(
    DailyWordProgress.bubbleBadgeText(masteredToday: 20, quota: 20, isReview: false),
    "今日已完成",
    "completed daily word bubble should show completion instead of 20/20"
)
expectEqual(
    DailyWordProgress.bubbleBadgeText(masteredToday: 20, quota: 40, isReview: false),
    "21/40",
    "expanded daily group should continue from 21/40"
)
expectEqual(
    DailyWordProgress.bubbleBadgeText(masteredToday: 1, quota: 20, isReview: true),
    "复习",
    "review bubble should not count against the daily 20 new words"
)

print("DailyWordProgressTests passed")
