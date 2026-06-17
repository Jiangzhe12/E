enum DailyWordProgress {
    static func statusText(masteredToday: Int, quota: Int, hasAvailableCard: Bool) -> String {
        if masteredToday >= quota {
            return "今日已完成"
        }
        guard hasAvailableCard else { return "今日暂无可学习单词" }
        return "今日单词 \(nextDailyWordIndex(masteredToday: masteredToday, quota: quota))/\(quota)"
    }

    static func bubbleBadgeText(masteredToday: Int, quota: Int, isReview: Bool) -> String {
        if isReview { return "复习" }
        if masteredToday >= quota {
            return "今日已完成"
        }
        return "\(nextDailyWordIndex(masteredToday: masteredToday, quota: quota))/\(quota)"
    }

    static func completionMessage(quota: Int, groupSize: Int = 20) -> String {
        "今天 \(quota) 个单词已完成，可以学习下一组 \(groupSize) 个，或明天继续新的 \(groupSize) 词"
    }

    private static func nextDailyWordIndex(masteredToday: Int, quota: Int) -> Int {
        min(max(masteredToday, 0) + 1, quota)
    }
}
