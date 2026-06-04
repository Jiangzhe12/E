import Foundation

enum ClaudeTranslationError: LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 Claude API Key"
        case .httpError(let status, let message):
            switch status {
            case 401: return "API Key 无效"
            case 429: return "请求过于频繁，请稍后再试"
            case 500...: return "Claude 服务暂时不可用"
            default: return "请求失败（\(status)）：\(message)"
            }
        case .emptyResponse:
            return "Claude 返回了空结果"
        }
    }
}

/// Translates via the Claude API (`POST /v1/messages`) with a JSON-schema
/// structured output, so the reply is guaranteed parseable. Besides the
/// translation itself it returns learner-oriented extras (phonetic,
/// short usage notes, an example sentence) that fit the app's
/// `TranslationResult` shape.
struct ClaudeTranslationProvider {
    static let defaultModel = "claude-opus-4-8"
    static let availableModels = [
        "claude-opus-4-8",
        "claude-sonnet-4-6",
        "claude-haiku-4-5"
    ]

    let apiKey: String
    let model: String

    var providerLabel: String { "Claude · \(model)" }

    /// Structured shape Claude is constrained to return.
    private struct Payload: Decodable {
        let translatedText: String
        let phonetic: String?
        let explanations: [String]
        let example: String?
    }

    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String
        }
        let error: APIError
    }

    func translate(_ text: String, direction: TranslationDirection) async throws -> TranslationResult {
        guard !apiKey.isEmpty else { throw ClaudeTranslationError.missingAPIKey }

        let systemPrompt: String
        switch direction {
        case .englishToChinese:
            systemPrompt = """
            你是一名服务于中文母语者的英语学习助手。把用户给出的英文内容翻译成自然流畅的简体中文。
            - translatedText：中文译文。
            - phonetic：若输入是单个单词或短语，给出美式音标（形如 /ˈsʌmθɪŋ/），否则为 null。
            - explanations：1-3 条简短中文讲解（词义辨析、常见搭配、语法点或地道用法），帮助学习者理解。
            - example：若输入是单词或短语，给出一个简短英文例句并附中文翻译，否则为 null。
            """
        case .chineseToEnglish:
            systemPrompt = """
            你是一名服务于中文母语者的英语学习助手。把用户给出的中文内容翻译成自然地道的英文。
            - translatedText：英文译文。
            - phonetic：始终为 null。
            - explanations：1-3 条简短中文讲解（用词选择、可替换表达或语气差异），帮助学习者掌握表达。
            - example：若译文中有值得学习的关键词或短语，给出一个使用它的英文例句并附中文翻译，否则为 null。
            """
        }

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "translatedText": ["type": "string"],
                "phonetic": ["type": ["string", "null"]],
                "explanations": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "example": ["type": ["string", "null"]]
            ],
            "required": ["translatedText", "phonetic", "explanations", "example"],
            "additionalProperties": false
        ]

        let body: [String: Any] = [
            "model": model,
            // Translations are deliberately short outputs.
            "max_tokens": 2048,
            "system": systemPrompt,
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": schema
                ]
            ],
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message ?? ""
            throw ClaudeTranslationError.httpError(httpResponse.statusCode, message)
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let jsonText = decoded.content.first(where: { $0.type == "text" })?.text,
              let payloadData = jsonText.data(using: .utf8) else {
            throw ClaudeTranslationError.emptyResponse
        }

        let payload = try JSONDecoder().decode(Payload.self, from: payloadData)
        let translated = payload.translatedText.trimmed
        guard !translated.isEmpty else { throw ClaudeTranslationError.emptyResponse }

        var explanations = payload.explanations.map(\.trimmed).filter { !$0.isEmpty }
        if let example = payload.example?.trimmed, !example.isEmpty {
            explanations.append("例句：\(example)")
        }

        return TranslationResult(
            originalText: text,
            translatedText: translated,
            phonetic: payload.phonetic?.trimmed,
            explanations: explanations,
            provider: providerLabel,
            direction: direction
        )
    }
}
