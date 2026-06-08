import Foundation

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
    /// Human-readable notice if a higher-priority provider failed and we fell
    /// back to another one; nil when the first choice succeeded.
    let onlineNotice: String?
}

/// Orchestrates translation across providers, best-first:
/// 1. ECDICT offline dictionary — English words/short phrases (instant, free)
/// 2. Claude API — sentences, ZH→EN, and dictionary misses (needs API key)
/// 3. MyMemory — free online fallback when Claude is unconfigured or fails
/// The winning provider is recorded in `TranslationResult.provider` so the UI
/// can show where each translation came from.
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

    /// True for inputs the offline dictionary can answer: English words or
    /// short phrases ("take off", "state-of-the-art"), up to 3 words.
    static func isDictionaryLookup(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1 ... 3).contains(words.count) else { return false }
        let allowed = CharacterSet.letters
            .union(CharacterSet(charactersIn: "-'’ "))
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
            && text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private let enableOnlineFallback: Bool
    private let ecdict = ECDICTDictionary()
    private var claudeAPI: ClaudeTranslationProvider?
    private var claudeCLI: ClaudeCLITranslationProvider?

    init(enableOnlineFallback: Bool) {
        self.enableOnlineFallback = enableOnlineFallback
    }

    /// Called at startup and whenever the user changes the translation engine,
    /// API key, or model in settings. Selects which AI provider (if any) sits
    /// between the offline dictionary and the MyMemory fallback.
    func updateConfiguration(engine: TranslationEngine, apiKey: String, model: String) {
        let resolvedModel = model.trimmed.isEmpty ? ClaudeTranslationShared.defaultModel : model.trimmed
        switch engine {
        case .localCLI:
            claudeCLI = ClaudeCLITranslationProvider(model: resolvedModel)
            claudeAPI = nil
        case .apiKey:
            let trimmedKey = apiKey.trimmed
            claudeAPI = trimmedKey.isEmpty
                ? nil
                : ClaudeTranslationProvider(apiKey: trimmedKey, model: resolvedModel)
            claudeCLI = nil
        case .freeOnly:
            claudeAPI = nil
            claudeCLI = nil
        }
    }

    /// Runs whichever Claude provider is configured (API or local CLI), or
    /// returns nil when the engine is free-only / unconfigured.
    private func aiTranslate(_ text: String, direction: TranslationDirection) async throws -> TranslationResult? {
        if let claudeAPI {
            return try await claudeAPI.translate(text, direction: direction)
        }
        if let claudeCLI {
            return try await claudeCLI.translate(text, direction: direction)
        }
        return nil
    }

    func translate(_ text: String, direction override: TranslationDirection? = nil) async throws -> TranslationOutcome {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else {
            throw TranslationServiceError.emptyInput
        }

        let direction = override ?? Self.detectDirection(trimmed)
        var notices: [String] = []

        // 1. Offline dictionary — only holds English headwords.
        if direction == .englishToChinese,
           Self.isDictionaryLookup(trimmed),
           let entry = await ecdict.lookup(trimmed.normalizedForLookup) {
            return TranslationOutcome(
                result: Self.makeResult(from: entry, originalText: trimmed, direction: direction),
                onlineNotice: nil
            )
        }

        guard enableOnlineFallback else {
            return Self.makeFallbackOutcome(for: trimmed, direction: direction, notices: notices, onlineEnabled: false)
        }

        // 2. Claude (API or local CLI) — best quality, learner-oriented extras.
        do {
            if let result = try await aiTranslate(trimmed, direction: direction) {
                return TranslationOutcome(result: result, onlineNotice: nil)
            }
        } catch {
            let reason = Self.describeOnlineError(error)
            NSLog("[TranslationService] Claude lookup failed: %@", reason)
            notices.append("Claude 翻译失败（\(reason)），已回退到 MyMemory。")
        }

        // 3. MyMemory — free machine translation, no key required.
        do {
            let result = try await translateWithMyMemory(trimmed, direction: direction)
            return TranslationOutcome(result: result, onlineNotice: notices.last)
        } catch {
            let reason = Self.describeOnlineError(error)
            NSLog("[TranslationService] MyMemory lookup failed: %@", reason)
            notices.append("在线翻译暂不可用（\(reason)）。")
        }

        return Self.makeFallbackOutcome(for: trimmed, direction: direction, notices: notices, onlineEnabled: true)
    }

    private static func makeResult(
        from entry: ECDICTEntry,
        originalText: String,
        direction: TranslationDirection
    ) -> TranslationResult {
        var explanations = entry.definition?
            .split(separator: "\n")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty } ?? []
        if let tag = entry.tag {
            explanations.append("考试标签：\(Self.describeTags(tag))")
        }
        return TranslationResult(
            originalText: originalText,
            translatedText: entry.translation,
            phonetic: entry.phonetic,
            explanations: explanations,
            provider: "ECDICT 本地词典",
            direction: direction
        )
    }

    private static let tagNames: [String: String] = [
        "zk": "中考", "gk": "高考", "ky": "考研",
        "cet4": "四级", "cet6": "六级",
        "toefl": "托福", "ielts": "雅思", "gre": "GRE"
    ]

    private static func describeTags(_ tag: String) -> String {
        tag.split(separator: " ")
            .map { tagNames[String($0)] ?? String($0) }
            .joined(separator: " / ")
    }

    private static func makeFallbackOutcome(
        for text: String,
        direction: TranslationDirection,
        notices: [String],
        onlineEnabled: Bool
    ) -> TranslationOutcome {
        let notice = notices.isEmpty ? nil : notices.joined(separator: " ")
        return TranslationOutcome(
            result: TranslationResult(
                originalText: text,
                translatedText: "暂无翻译结果：\(text)",
                phonetic: nil,
                explanations: notice.map { [$0] } ?? ["本地词典未收录此内容。"],
                provider: onlineEnabled ? "Fallback (online unavailable)" : "Fallback",
                direction: direction
            ),
            onlineNotice: notice
        )
    }

    private static func describeOnlineError(_ error: Error) -> String {
        if let claudeError = error as? ClaudeTranslationError {
            return claudeError.localizedDescription
        }
        if let cliError = error as? ClaudeCLIError {
            return cliError.localizedDescription
        }
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
