import Foundation

/// Single source of truth for the user's weekly study rhythm ("学习日 / 休息日").
///
/// Weekday integers follow `Calendar`'s convention: Sunday = 1 … Saturday = 7.
/// Both `WordCarouselStore` decks and `AppModel` (streak, rest-day UI) read the
/// same configuration so scheduling, streaks, and UI never disagree.
enum LearningSchedule {
    /// UserDefaults key holding the study weekdays as an `[Int]`.
    static let studyDaysDefaultsKey = "learning.studyDays"

    /// Default rhythm: study Monday–Thursday, rest Friday/Saturday/Sunday.
    /// (Monday = 2 … Thursday = 5 in `Calendar`'s Sunday-first numbering.)
    static let defaultStudyDays: Set<Int> = [2, 3, 4, 5]

    /// The configured study weekdays, or the default if none has been saved.
    static func studyDays(defaults: UserDefaults = .standard) -> Set<Int> {
        guard let stored = defaults.array(forKey: studyDaysDefaultsKey) as? [Int],
              !stored.isEmpty else {
            return defaultStudyDays
        }
        return Set(stored)
    }

    /// Persist the study weekdays (stored sorted for stable, readable defaults).
    static func setStudyDays(_ days: Set<Int>, defaults: UserDefaults = .standard) {
        defaults.set(Array(days).sorted(), forKey: studyDaysDefaultsKey)
    }

    /// UserDefaults key holding the daily total ceiling for the word deck.
    static let dailyBudgetDefaultsKey = "learning.dailyWordBudget"

    /// Default daily ceiling (reviews + new words) for the word deck.
    static let defaultDailyBudget = 40

    /// Allowed range for the configurable daily ceiling.
    static let dailyBudgetRange = 10...100

    /// The configured daily ceiling, or the default if none/invalid is saved.
    static func dailyBudget(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: dailyBudgetDefaultsKey)
        return stored > 0 ? stored : defaultDailyBudget
    }

    static func setDailyBudget(_ value: Int, defaults: UserDefaults = .standard) {
        let clamped = min(dailyBudgetRange.upperBound, max(dailyBudgetRange.lowerBound, value))
        defaults.set(clamped, forKey: dailyBudgetDefaultsKey)
    }

    /// Whether `date` falls on a study day.
    ///
    /// An empty configuration is treated as "every day is a study day" so the
    /// scheduler can never deadlock (e.g. roll-forward searching for a study
    /// day that doesn't exist).
    static func isStudyDay(_ date: Date, calendar: Calendar, defaults: UserDefaults = .standard) -> Bool {
        let days = studyDays(defaults: defaults)
        guard !days.isEmpty else { return true }
        return days.contains(calendar.component(.weekday, from: date))
    }
}
