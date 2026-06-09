import Foundation

/// A single high-frequency spoken "chunk" — the half-finished sentences the
/// brain actually reaches for in a real conversation. Unlike single words,
/// these are memorised and recalled as one unit, which is what makes speaking
/// feel fast instead of word-by-word assembled.
///
/// `id` is the normalised English string and doubles as the SRS key, so the
/// generic `WordCarouselStore` can schedule phrases exactly like it schedules
/// words — no second scheduler needed.
struct MeetingPhraseCard: Identifiable {
    /// Normalised English (lowercased, trimmed) — the SRS key.
    let id: String
    let english: String
    let chinese: String
    /// When to reach for this chunk, in Chinese. Shown on the card *front* so
    /// the user practises producing the English from the situation, not just
    /// recognising it.
    let scenario: String
    let example: String
    let category: MeetingPhraseCategory
    var isMastered: Bool = false
    var isReview: Bool = false
}

enum MeetingPhraseCategory: String, CaseIterable {
    case clarify
    case buyTime
    case opinion
    case wrapUp
    case smallTalk

    var title: String {
        switch self {
        case .clarify: return "没听清 / 确认"
        case .buyTime: return "争取时间"
        case .opinion: return "表态 / 异议"
        case .wrapUp: return "收尾 / 下一步"
        case .smallTalk: return "寒暄"
        }
    }

    var systemImage: String {
        switch self {
        case .clarify: return "questionmark.bubble"
        case .buyTime: return "hourglass"
        case .opinion: return "hand.raised"
        case .wrapUp: return "checklist"
        case .smallTalk: return "hand.wave"
        }
    }
}

/// Curated bank of meeting / call survival chunks. These are the few dozen
/// moves that come up over and over in real work meetings — getting them to
/// roll off the tongue does more for "being able to keep up in a call" than
/// hundreds more vocabulary words.
enum MeetingPhraseBank {
    static let cards: [MeetingPhraseCard] = build()
    static let allIDs: [String] = cards.map { $0.id }

    private static let byID: [String: MeetingPhraseCard] =
        Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// Look up a card by its (possibly un-normalised) SRS key. Returns `nil`
    /// for keys that aren't in the bank (e.g. stale persisted state after the
    /// bank changes).
    static func card(forID id: String) -> MeetingPhraseCard? {
        byID[normalize(id)]
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func build() -> [MeetingPhraseCard] {
        raw.map { entry in
            MeetingPhraseCard(
                id: normalize(entry.english),
                english: entry.english,
                chinese: entry.chinese,
                scenario: entry.scenario,
                example: entry.example,
                category: entry.category
            )
        }
    }

    private struct RawPhrase {
        let english: String
        let chinese: String
        let scenario: String
        let example: String
        let category: MeetingPhraseCategory
    }

    private static let raw: [RawPhrase] = [
        // MARK: - 没听清 / 确认理解
        RawPhrase(
            english: "Sorry, could you say that again?",
            chinese: "抱歉，能再说一遍吗？",
            scenario: "没听清对方刚说的话，想请对方重复",
            example: "Sorry, could you say that again? The audio dropped for a second.",
            category: .clarify
        ),
        RawPhrase(
            english: "Just to make sure I understand,",
            chinese: "我确认一下我的理解，",
            scenario: "想把对方的意思复述一遍确认对不对",
            example: "Just to make sure I understand, you want the report by Friday?",
            category: .clarify
        ),
        RawPhrase(
            english: "Do you mean that ...?",
            chinese: "你的意思是……？",
            scenario: "不确定对方的具体意图，想澄清",
            example: "Do you mean that we should pause the launch until next week?",
            category: .clarify
        ),
        RawPhrase(
            english: "Sorry, you cut out for a second.",
            chinese: "抱歉，你刚刚断了一下。",
            scenario: "远程会议里对方网络卡顿、声音断了",
            example: "Sorry, you cut out for a second — could you repeat the last part?",
            category: .clarify
        ),
        RawPhrase(
            english: "Could you go over that one more time?",
            chinese: "能再讲一遍那部分吗？",
            scenario: "某个点没跟上，想请对方再说一次",
            example: "Could you go over that one more time? I want to get the numbers right.",
            category: .clarify
        ),

        // MARK: - 争取时间 / 思考
        RawPhrase(
            english: "That's a good question — let me think for a second.",
            chinese: "好问题，让我想一下。",
            scenario: "被当场提问，需要几秒钟组织答案",
            example: "That's a good question — let me think for a second.",
            category: .buyTime
        ),
        RawPhrase(
            english: "Let me get back to you on that.",
            chinese: "这个我回头答复你。",
            scenario: "当下答不上来，想之后再回复",
            example: "I don't have the figure handy — let me get back to you on that.",
            category: .buyTime
        ),
        RawPhrase(
            english: "Give me a moment to pull that up.",
            chinese: "稍等，我调出来看一下。",
            scenario: "需要现场查一下文档或数据",
            example: "Give me a moment to pull that up and I'll share my screen.",
            category: .buyTime
        ),
        RawPhrase(
            english: "Let me rephrase that.",
            chinese: "我换个说法。",
            scenario: "发现自己刚才没说清楚，想重说",
            example: "That didn't come out right — let me rephrase that.",
            category: .buyTime
        ),

        // MARK: - 表态 / 同意 / 异议
        RawPhrase(
            english: "I agree, and I'd add that ...",
            chinese: "我同意，还想补充一点……",
            scenario: "赞同对方并想补充自己的观点",
            example: "I agree, and I'd add that we should loop in the design team early.",
            category: .opinion
        ),
        RawPhrase(
            english: "I see your point, but ...",
            chinese: "我理解你的意思，不过……",
            scenario: "委婉地表达不同意见",
            example: "I see your point, but I think the timeline is too tight.",
            category: .opinion
        ),
        RawPhrase(
            english: "That makes sense to me.",
            chinese: "这个我觉得有道理。",
            scenario: "表示认同对方的说法",
            example: "That makes sense to me — let's go with that approach.",
            category: .opinion
        ),
        RawPhrase(
            english: "I'm not sure I follow.",
            chinese: "我不太跟得上你的逻辑。",
            scenario: "没理解对方的推理，想让对方解释",
            example: "I'm not sure I follow — why would that delay the release?",
            category: .opinion
        ),
        RawPhrase(
            english: "Can I jump in here?",
            chinese: "我能插一句吗？",
            scenario: "想在别人发言时礼貌地插话",
            example: "Can I jump in here? I have some context on that.",
            category: .opinion
        ),
        RawPhrase(
            english: "Correct me if I'm wrong, but ...",
            chinese: "如果我说错了请纠正，但是……",
            scenario: "不太确定时谨慎地提出观点",
            example: "Correct me if I'm wrong, but didn't we agree on this last week?",
            category: .opinion
        ),
        RawPhrase(
            english: "From my side, ...",
            chinese: "从我这边来看，……",
            scenario: "表达自己负责的部分的进展或立场",
            example: "From my side, everything is ready for the demo.",
            category: .opinion
        ),

        // MARK: - 收尾 / 下一步
        RawPhrase(
            english: "So, to summarize, ...",
            chinese: "那么，总结一下，……",
            scenario: "会议接近尾声时归纳要点",
            example: "So, to summarize, we'll ship the fix today and review on Monday.",
            category: .wrapUp
        ),
        RawPhrase(
            english: "What are the next steps?",
            chinese: "接下来的步骤是什么？",
            scenario: "推动会议产出明确的行动项",
            example: "Sounds good — what are the next steps from here?",
            category: .wrapUp
        ),
        RawPhrase(
            english: "Who's going to own this?",
            chinese: "这个由谁负责？",
            scenario: "确认某项任务的负责人",
            example: "Okay, who's going to own this and by when?",
            category: .wrapUp
        ),
        RawPhrase(
            english: "Let's take this offline.",
            chinese: "这个我们会后单独聊。",
            scenario: "话题不适合在会上展开，想另约时间",
            example: "This is a bigger discussion — let's take this offline.",
            category: .wrapUp
        ),
        RawPhrase(
            english: "Are we all on the same page?",
            chinese: "我们理解一致吗？",
            scenario: "结束前确认大家达成共识",
            example: "Before we wrap up, are we all on the same page?",
            category: .wrapUp
        ),
        RawPhrase(
            english: "Let me know if I missed anything.",
            chinese: "如果我漏了什么请告诉我。",
            scenario: "总结之后给对方补充的机会",
            example: "That's everything from me — let me know if I missed anything.",
            category: .wrapUp
        ),

        // MARK: - 寒暄 / 闲聊
        RawPhrase(
            english: "Thanks for joining.",
            chinese: "感谢参加。",
            scenario: "会议开场对大家表示感谢",
            example: "Thanks for joining, everyone — let's get started.",
            category: .smallTalk
        ),
        RawPhrase(
            english: "How's your week going?",
            chinese: "你这周过得怎么样？",
            scenario: "会前和同事简单寒暄",
            example: "Hey, good to see you — how's your week going?",
            category: .smallTalk
        ),
        RawPhrase(
            english: "Can everyone hear me okay?",
            chinese: "大家能听清我说话吗？",
            scenario: "远程会议开场确认音频正常",
            example: "Can everyone hear me okay? Let me know if I'm too quiet.",
            category: .smallTalk
        ),
        RawPhrase(
            english: "Sorry I'm a bit late.",
            chinese: "抱歉我来晚了一点。",
            scenario: "迟到加入会议时简单致歉",
            example: "Sorry I'm a bit late — please go on.",
            category: .smallTalk
        ),
        RawPhrase(
            english: "Let's give it a minute for others to join.",
            chinese: "我们等一下其他人加入。",
            scenario: "会议开始前等待其他与会者",
            example: "Let's give it a minute for others to join before we start.",
            category: .smallTalk
        ),
        RawPhrase(
            english: "Have a good one!",
            chinese: "回头见！/ 祝你顺利！",
            scenario: "会议结束时轻松地道别",
            example: "Thanks everyone — have a good one!",
            category: .smallTalk
        )
    ]
}
