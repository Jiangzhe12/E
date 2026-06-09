import Foundation

/// One Chinese→English production prompt. The user reads the Chinese, produces
/// English from scratch (the hard part of speaking), then an AI coach grades
/// the attempt. `reference` is a model answer revealed afterwards — the grader
/// is told to improve on the *user's* wording, not just echo this.
struct ProductionDrill: Identifiable {
    let id: String
    let chinese: String
    let reference: String
    let hint: String?
    let category: MeetingPhraseCategory
}

enum ProductionVerdict {
    case great
    case good
    case needsWork

    var title: String {
        switch self {
        case .great: return "很地道"
        case .good: return "基本可用"
        case .needsWork: return "可以更好"
        }
    }

    /// Maps the loosely-specified string the model returns onto a fixed set,
    /// defaulting to `.good` so an unexpected label never breaks the UI.
    static func from(_ raw: String) -> ProductionVerdict {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "great", "excellent", "perfect": return .great
        case "needs_work", "needs work", "poor", "weak": return .needsWork
        default: return .good
        }
    }
}

/// AI coach's assessment of a single attempt.
struct ProductionGrade {
    let verdict: ProductionVerdict
    /// A natural English version, ideally built on what the user wrote.
    let polished: String
    /// 1-3 short Chinese feedback points (what to fix and why).
    let notes: [String]
    /// One short encouraging line, if the model offered one.
    let encouragement: String?
    let provider: String
}

enum ProductionGradeError: LocalizedError {
    case noProvider

    var errorDescription: String? {
        switch self {
        case .noProvider:
            return "中译英批改需要 AI 引擎。请在设置中选择「本地 Claude CLI」或填入 Claude API Key。"
        }
    }
}

/// Prompt construction + response parsing shared by the API and local-CLI
/// grading paths — mirrors how `ClaudeTranslationShared` is reused for
/// translation.
enum ProductionGradeShared {
    static let systemPrompt = """
    你是一名服务于中文母语者的英语口语 / 写作教练。用户正在做「中译英」练习：\
    我会给出中文原意、一个参考答案，以及用户自己写的英文作答。请评估用户的作答。

    评估要点：是否准确传达了中文原意；是否自然地道（而非中式英语）；语法、用词、时态、语气是否恰当。\
    评分基于「用户的作答」，不要因为它和参考答案不同就扣分——只要自然、达意即可算好。

    字段说明：
    - verdict：great（很地道，几乎不用改）/ good（达意但可优化）/ needs_work（有明显问题或没说清）。
    - polished：一个自然地道的英文版本。尽量在用户原句基础上改进，保留对的部分；只有当用户作答完全偏离时才另写。
    - notes：1-3 条简短中文反馈，具体指出问题和更好的说法（例如某个词更自然、某处语法、语气更礼貌）。若作答已经很好，可给 1 条点出亮点。
    - encouragement：一句简短的中文鼓励（可选，可为 null）。
    """

    /// JSON Schema for the API provider's structured output.
    static var jsonSchema: [String: Any] {[
        "type": "object",
        "properties": [
            "verdict": ["type": "string", "enum": ["great", "good", "needs_work"]],
            "polished": ["type": "string"],
            "notes": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "encouragement": ["type": ["string", "null"]]
        ],
        "required": ["verdict", "polished", "notes", "encouragement"],
        "additionalProperties": false
    ]}

    /// Spelled-out contract for the CLI path (its output isn't schema-constrained).
    static let jsonInstruction = """


    请只输出一个 JSON 对象，不要使用 markdown 代码块或任何额外文字。字段：\
    verdict（"great" / "good" / "needs_work"）、polished（字符串）、\
    notes（字符串数组）、encouragement（字符串或 null）。
    """

    /// The labelled text handed to the model on stdin / as the user message.
    static func userContent(chinese: String, reference: String, attempt: String) -> String {
        """
        【中文原意】\(chinese)
        【参考答案】\(reference)
        【我的英文作答】\(attempt)
        """
    }

    private struct Payload: Decodable {
        let verdict: String
        let polished: String
        let notes: [String]
        let encouragement: String?
    }

    static func grade(fromJSONText jsonText: String, provider: String) throws -> ProductionGrade {
        let cleaned = extractJSONObject(jsonText)
        guard let data = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ClaudeCLIError.emptyResponse
        }

        let polished = payload.polished.trimmed
        let notes = payload.notes.map(\.trimmed).filter { !$0.isEmpty }
        let encouragement = payload.encouragement?.trimmed
        return ProductionGrade(
            verdict: ProductionVerdict.from(payload.verdict),
            polished: polished,
            notes: notes,
            encouragement: (encouragement?.isEmpty ?? true) ? nil : encouragement,
            provider: provider
        )
    }

    /// Strip markdown fences and slice to the outermost `{...}` — same tolerance
    /// the translation path applies to chatty CLI replies.
    private static func extractJSONObject(_ raw: String) -> String {
        var text = raw.trimmed
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let closingFence = text.range(of: "```", options: .backwards) {
                text = String(text[..<closingFence.lowerBound])
            }
            text = text.trimmed
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            return String(text[start ... end])
        }
        return text
    }
}

/// Work / meeting-flavoured Chinese→English drills, sharing categories with the
/// chunk bank so the route feels like one continuous theme: recognise the chunk
/// in stage 1, produce a full sentence under grading here in stage 3.
enum ProductionDrillBank {
    static let all: [ProductionDrill] = [
        ProductionDrill(id: "d-clarify-repeat", chinese: "抱歉，你刚才那部分能再说一遍吗？", reference: "Sorry, could you say that last part again?", hint: "用 could you ... 更礼貌", category: .clarify),
        ProductionDrill(id: "d-clarify-confirm", chinese: "我确认一下：你是想让我周五前把报告发出去，对吗？", reference: "Just to confirm, you want me to send the report by Friday, right?", hint: "Just to confirm, ...", category: .clarify),
        ProductionDrill(id: "d-clarify-follow", chinese: "我不太跟得上，为什么这样会拖慢上线？", reference: "I'm not sure I follow — why would that slow down the launch?", hint: nil, category: .clarify),
        ProductionDrill(id: "d-buytime-think", chinese: "这个问题不错，让我想几秒钟。", reference: "That's a good question — let me think for a second.", hint: nil, category: .buyTime),
        ProductionDrill(id: "d-buytime-getback", chinese: "这个数据我手头没有，回头答复你。", reference: "I don't have that number on hand — let me get back to you.", hint: "get back to you", category: .buyTime),
        ProductionDrill(id: "d-buytime-pullup", chinese: "稍等，我把文件调出来。", reference: "Give me a moment to pull that up.", hint: nil, category: .buyTime),
        ProductionDrill(id: "d-opinion-agree", chinese: "我同意，但我担心时间太紧。", reference: "I agree, but I'm worried the timeline is too tight.", hint: nil, category: .opinion),
        ProductionDrill(id: "d-opinion-differ", chinese: "我大致理解你的意思，不过我有点不同看法。", reference: "I see what you mean, but I have a slightly different view.", hint: "I see what you mean, but ...", category: .opinion),
        ProductionDrill(id: "d-opinion-jumpin", chinese: "我能插一句吗？", reference: "Can I jump in here?", hint: nil, category: .opinion),
        ProductionDrill(id: "d-opinion-correct", chinese: "如果我理解错了请纠正，我们上周不是已经定了吗？", reference: "Correct me if I'm wrong, but didn't we already decide this last week?", hint: "Correct me if I'm wrong, but ...", category: .opinion),
        ProductionDrill(id: "d-opinion-ready", chinese: "我这边的部分都准备好做演示了。", reference: "Everything on my side is ready for the demo.", hint: "on my side", category: .opinion),
        ProductionDrill(id: "d-wrapup-summary", chinese: "那我快速总结一下今天定的事。", reference: "Let me quickly summarize what we decided today.", hint: "to summarize, ...", category: .wrapUp),
        ProductionDrill(id: "d-wrapup-owner", chinese: "接下来这件事谁来负责？", reference: "Who's going to own this going forward?", hint: "own this", category: .wrapUp),
        ProductionDrill(id: "d-wrapup-offline", chinese: "这个我们会后单独聊吧。", reference: "Let's take this offline.", hint: "take this offline", category: .wrapUp),
        ProductionDrill(id: "d-wrapup-samepage", chinese: "结束之前，我们理解一致吗？", reference: "Before we wrap up, are we all on the same page?", hint: "on the same page", category: .wrapUp),
        ProductionDrill(id: "d-wrapup-delay", chinese: "我们可能得把上线推迟到下周。", reference: "We may need to push the launch to next week.", hint: "push ... to", category: .wrapUp),
        ProductionDrill(id: "d-smalltalk-thanks", chinese: "感谢大家参加，我们开始吧。", reference: "Thanks for joining, everyone — let's get started.", hint: nil, category: .smallTalk),
        ProductionDrill(id: "d-smalltalk-late", chinese: "抱歉我来晚了一点，你们继续。", reference: "Sorry I'm a bit late — please go on.", hint: nil, category: .smallTalk)
    ]
}
