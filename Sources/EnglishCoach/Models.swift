import Foundation

enum TranslationDirection: String {
    case englishToChinese = "en→zh"
    case chineseToEnglish = "zh→en"

    var displayLabel: String {
        switch self {
        case .englishToChinese: return "英→中"
        case .chineseToEnglish: return "中→英"
        }
    }

    var langpair: String {
        switch self {
        case .englishToChinese: return "en|zh-CN"
        case .chineseToEnglish: return "zh-CN|en"
        }
    }
}

enum TranslationDirectionChoice: String, CaseIterable, Identifiable {
    case auto = "auto"
    case englishToChinese = "en→zh"
    case chineseToEnglish = "zh→en"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .auto: return "自动"
        case .englishToChinese: return "英→中"
        case .chineseToEnglish: return "中→英"
        }
    }

    /// Returns a concrete direction, or `nil` for auto-detect.
    var concreteDirection: TranslationDirection? {
        switch self {
        case .auto: return nil
        case .englishToChinese: return .englishToChinese
        case .chineseToEnglish: return .chineseToEnglish
        }
    }
}

struct TranslationResult: Identifiable {
    let id = UUID()
    let originalText: String
    let translatedText: String
    let phonetic: String?
    let explanations: [String]
    let provider: String
    let direction: TranslationDirection
}

struct LookupHistoryItem: Identifiable {
    let id: Int64
    let rawText: String
    let normalizedText: String
    let sourceApp: String?
    let translation: String
    let phonetic: String?
    let explanations: [String]
    let createdAt: Date
}

struct SelectedTextSnapshot {
    let text: String
    let sourceAppName: String?
}

enum HotkeyStatus {
    case registered
    case failed(String)
}

/// Where the translation result shows up after ⌘C⌘C triggers it.
enum TranslationPresentation: String, CaseIterable, Identifiable, Codable {
    case floating
    case mainWindow

    var id: String { rawValue }
}

/// Time window for filtering the history sidebar.
enum HistoryTimeFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .today: return "今日"
        case .thisWeek: return "本周"
        }
    }
}

enum InterestTopic: String, CaseIterable, Identifiable {
    case movies
    case technology
    case travel
    case gaming
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: return "电影"
        case .technology: return "科技"
        case .travel: return "旅行"
        case .gaming: return "游戏"
        case .music: return "音乐"
        }
    }

    var accentKeyword: String {
        switch self {
        case .movies: return "cinematic"
        case .technology: return "innovation"
        case .travel: return "explore"
        case .gaming: return "strategy"
        case .music: return "rhythm"
        }
    }
}

struct LessonPhrase: Identifiable {
    let id = UUID()
    let english: String
    let chinese: String
    let example: String
}

struct InterestLesson: Identifiable {
    let id = UUID()
    let templateID: String
    let topic: InterestTopic
    let title: String
    let warmup: String
    let passage: String
    let phrases: [LessonPhrase]
    let question: String
    let options: [String]
    let answerIndex: Int
    let explanation: String
}

struct LearningAttemptRecord: Identifiable, Codable {
    let id: UUID
    let lessonTemplateID: String
    let topicRawValue: String
    let lessonTitle: String
    let question: String
    let selectedOption: String
    let correctOption: String
    let isCorrect: Bool
    let isReview: Bool
    let createdAt: Date

    var topic: InterestTopic {
        InterestTopic(rawValue: topicRawValue) ?? .movies
    }
}

struct DesktopWordCard: Identifiable {
    var id: String { word }
    let word: String
    var meaning: String
    var phonetic: String?
    var explanation: String
    var example: String
    var provider: String
    var isMastered: Bool
    /// True when this card came from the SRS review-due pool rather than the
    /// fresh "today's words" pool. UI uses this to switch the action buttons
    /// from "标记熟悉" to "还记得 / 忘了".
    var isReview: Bool = false
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedForLookup: String {
        trimmed.lowercased()
    }
}

extension Date {
    /// Human-friendly Chinese description that scales with how long ago the
    /// date is: "刚刚" / "5 分钟前" / "今天 14:30" / "昨天 09:12" / "3 天前" /
    /// absolute date for anything older than a week.
    var relativeDescription: String {
        let calendar = Calendar.current
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 60 {
            return "刚刚"
        }
        if interval < 60 * 60 {
            return "\(Int(interval / 60)) 分钟前"
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"

        if calendar.isDateInToday(self) {
            return "今天 \(timeFormatter.string(from: self))"
        }
        if calendar.isDateInYesterday(self) {
            return "昨天 \(timeFormatter.string(from: self))"
        }

        let dayDiff = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: self),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if dayDiff > 0 && dayDiff < 7 {
            return "\(dayDiff) 天前"
        }

        let absoluteFormatter = DateFormatter()
        absoluteFormatter.locale = Locale(identifier: "zh_CN")
        absoluteFormatter.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        return absoluteFormatter.string(from: self)
    }
}
