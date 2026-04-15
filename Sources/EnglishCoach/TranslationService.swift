import Foundation

private struct LocalDictionaryEntry {
    let translatedText: String
    let phonetic: String?
    let explanations: [String]
}

private struct MyMemoryResponse: Decodable {
    struct ResponseData: Decodable {
        let translatedText: String
    }

    let responseData: ResponseData
}

enum TranslationServiceError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入要翻译的内容"
        }
    }
}

struct TranslationOutcome {
    let result: TranslationResult
    /// Human-readable notice if online fallback was attempted and failed; nil otherwise.
    let onlineNotice: String?
}

actor TranslationService {
    /// Detect whether the input is Chinese (→ translate to English) or English
    /// (→ translate to Chinese) based on the proportion of CJK characters.
    static func detectDirection(_ text: String) -> TranslationDirection {
        let nonWhitespace = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        guard !nonWhitespace.isEmpty else { return .englishToChinese }
        let cjkCount = nonWhitespace.filter { scalar in
            (0x4E00 ... 0x9FFF).contains(scalar.value)
                || (0x3400 ... 0x4DBF).contains(scalar.value)
                || (0xF900 ... 0xFAFF).contains(scalar.value)
        }.count
        return Double(cjkCount) / Double(nonWhitespace.count) > 0.3
            ? .chineseToEnglish
            : .englishToChinese
    }

    private let localDictionary: [String: LocalDictionaryEntry] = [
        "ability": LocalDictionaryEntry(translatedText: "能力", phonetic: "/əˈbɪləti/", explanations: ["the power or skill to do something"]),
        "achieve": LocalDictionaryEntry(translatedText: "实现；达成", phonetic: "/əˈtʃiːv/", explanations: ["to succeed in reaching a goal"]),
        "challenge": LocalDictionaryEntry(translatedText: "挑战", phonetic: "/ˈtʃælɪndʒ/", explanations: ["a difficult task that tests ability"]),
        "consistency": LocalDictionaryEntry(translatedText: "一致性；持续性", phonetic: "/kənˈsɪstənsi/", explanations: ["the quality of always being done in the same way"]),
        "curious": LocalDictionaryEntry(translatedText: "好奇的", phonetic: "/ˈkjʊriəs/", explanations: ["eager to know or learn"]),
        "develop": LocalDictionaryEntry(translatedText: "发展；培养", phonetic: "/dɪˈveləp/", explanations: ["to grow or improve over time"]),
        "effort": LocalDictionaryEntry(translatedText: "努力", phonetic: "/ˈefərt/", explanations: ["hard work to achieve something"]),
        "focus": LocalDictionaryEntry(translatedText: "专注", phonetic: "/ˈfoʊkəs/", explanations: ["to give full attention to something"]),
        "habit": LocalDictionaryEntry(translatedText: "习惯", phonetic: "/ˈhæbɪt/", explanations: ["something you do regularly"]),
        "improve": LocalDictionaryEntry(translatedText: "提升；改进", phonetic: "/ɪmˈpruːv/", explanations: ["to become better"]),
        "interest": LocalDictionaryEntry(translatedText: "兴趣", phonetic: "/ˈɪntrəst/", explanations: ["a feeling of wanting to know more"]),
        "language": LocalDictionaryEntry(translatedText: "语言", phonetic: "/ˈlæŋɡwɪdʒ/", explanations: ["a system of communication"]),
        "learn": LocalDictionaryEntry(translatedText: "学习", phonetic: "/lɜːrn/", explanations: ["to gain knowledge"]),
        "memory": LocalDictionaryEntry(translatedText: "记忆", phonetic: "/ˈmeməri/", explanations: ["the ability to remember"]),
        "motivation": LocalDictionaryEntry(translatedText: "动力", phonetic: "/ˌmoʊtɪˈveɪʃn/", explanations: ["the reason for doing something"]),
        "practice": LocalDictionaryEntry(translatedText: "练习", phonetic: "/ˈpræktɪs/", explanations: ["repeated activity to improve skill"]),
        "progress": LocalDictionaryEntry(translatedText: "进步", phonetic: "/ˈprɑːɡres/", explanations: ["movement toward improvement"]),
        "review": LocalDictionaryEntry(translatedText: "复习", phonetic: "/rɪˈvjuː/", explanations: ["to study something again"]),
        "translate": LocalDictionaryEntry(translatedText: "翻译", phonetic: "/trænsˈleɪt/", explanations: ["to change words into another language"]),
        "vocabulary": LocalDictionaryEntry(translatedText: "词汇", phonetic: "/voʊˈkæbjəleri/", explanations: ["all the words someone knows"]),
        "take off": LocalDictionaryEntry(translatedText: "起飞；脱下", phonetic: nil, explanations: ["to leave the ground in an aircraft", "to remove clothing"]),
        "look up": LocalDictionaryEntry(translatedText: "查找；查阅", phonetic: nil, explanations: ["to search for information"]),
        "stick to": LocalDictionaryEntry(translatedText: "坚持", phonetic: nil, explanations: ["to continue doing something"])
    ]

    private let enableOnlineFallback: Bool

    init(enableOnlineFallback: Bool) {
        self.enableOnlineFallback = enableOnlineFallback
    }

    func translate(_ text: String, direction override: TranslationDirection? = nil) async throws -> TranslationOutcome {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else {
            throw TranslationServiceError.emptyInput
        }

        let direction = override ?? Self.detectDirection(trimmed)

        // Local dictionary only has English keys — skip for ZH→EN.
        if direction == .englishToChinese {
            let normalized = trimmed.normalizedForLookup
            if let local = localDictionary[normalized] {
                return TranslationOutcome(
                    result: TranslationResult(
                        originalText: trimmed,
                        translatedText: local.translatedText,
                        phonetic: local.phonetic,
                        explanations: local.explanations,
                        provider: "Local Dictionary",
                        direction: direction
                    ),
                    onlineNotice: nil
                )
            }
        }

        var onlineNotice: String?
        if enableOnlineFallback {
            do {
                let onlineResult = try await translateWithMyMemory(trimmed, direction: direction)
                return TranslationOutcome(result: onlineResult, onlineNotice: nil)
            } catch {
                let reason = Self.describeOnlineError(error)
                NSLog("[TranslationService] online lookup failed: %@", reason)
                onlineNotice = "在线翻译暂不可用（\(reason)），已回退到本地词典。"
            }
        }

        return TranslationOutcome(
            result: TranslationResult(
                originalText: trimmed,
                translatedText: "暂无本地词典释义：\(trimmed)",
                phonetic: nil,
                explanations: onlineNotice.map { [$0] } ?? ["本地词典未收录此内容。"],
                provider: enableOnlineFallback ? "Fallback (online unavailable)" : "Fallback",
                direction: direction
            ),
            onlineNotice: onlineNotice
        )
    }

    private static func describeOnlineError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "请求超时"
            case .notConnectedToInternet, .networkConnectionLost: return "未连接到互联网"
            case .cannotFindHost, .dnsLookupFailed: return "DNS 解析失败"
            case .badServerResponse: return "服务响应异常"
            default: return "网络错误 \(urlError.code.rawValue)"
            }
        }
        if error is DecodingError {
            return "响应格式解析失败"
        }
        return error.localizedDescription
    }

    private func translateWithMyMemory(_ text: String, direction: TranslationDirection) async throws -> TranslationResult {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: direction.langpair)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        let translated = decoded.responseData.translatedText.decodingHTMLEntities().trimmed

        return TranslationResult(
            originalText: text,
            translatedText: translated.isEmpty ? "(无结果)" : translated,
            phonetic: nil,
            explanations: ["来自在线翻译服务"],
            provider: "MyMemory",
            direction: direction
        )
    }
}

private extension String {
    func decodingHTMLEntities() -> String {
        replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
