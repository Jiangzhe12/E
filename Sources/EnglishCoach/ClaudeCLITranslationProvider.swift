import Foundation

enum ClaudeCLIError: LocalizedError {
    case binaryNotFound
    case launchFailed(String)
    case nonZeroExit(Int32, String)
    case emptyResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "未找到 claude 命令行，请确认已安装并登录 Claude Code"
        case .launchFailed(let message):
            return "无法启动 claude：\(message)"
        case .nonZeroExit(let code, let message):
            let detail = message.trimmed.isEmpty ? "" : "：\(message.trimmed)"
            return "claude 退出码 \(code)\(detail)"
        case .emptyResponse:
            return "claude 返回了空结果"
        case .timedOut:
            return "claude 响应超时"
        }
    }
}

/// Translates by shelling out to the locally-installed Claude Code CLI in
/// headless mode (`claude -p --output-format json`). Reuses the user's existing
/// Claude Code login, so no API key is required — at the cost of CLI startup
/// latency (a few seconds per call).
///
/// The CLI is run through a login shell (`/bin/zsh -lc`) so the user's full
/// PATH / version-manager setup (volta, nvm, homebrew) resolves `claude` and
/// the node runtime it needs. The invocation disables Claude Code tools,
/// plugins, session persistence, and MCP config, then runs from an isolated
/// temporary directory so a translation request cannot inspect the app's source
/// tree or the user's current project. The text to translate is passed on stdin
/// and the instructions via a temp `--append-system-prompt-file`, so no user
/// content is ever interpolated into the shell command. A `perl alarm` wrapper
/// enforces a hard timeout (macOS has no `timeout` binary).
struct ClaudeCLITranslationProvider {
    let model: String

    var providerLabel: String { "本地 Claude CLI（安全隔离）" }

    private static let timeoutSeconds = 45

    func translate(_ text: String, direction: TranslationDirection) async throws -> TranslationResult {
        let systemPrompt = ClaudeTranslationShared.systemPrompt(for: direction) + Self.jsonInstruction

        let promptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ec-sysprompt-\(UUID().uuidString).txt")
        try systemPrompt.write(to: promptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        let command = Self.makeCommand(model: model, promptURL: promptURL)
        let stdout = try await Self.runLoginShell(command: command, stdin: text)

        // The CLI wraps the model output in an envelope; `.result` is the text.
        guard let data = stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let resultText = envelope.result?.trimmed,
              !resultText.isEmpty else {
            throw ClaudeCLIError.emptyResponse
        }

        return try ClaudeTranslationShared.result(
            fromJSONText: resultText,
            originalText: text,
            direction: direction,
            provider: providerLabel
        )
    }

    /// Grade a Chinese→English production attempt. Reuses the same hardened
    /// login-shell runner as `translate`, only swapping the system prompt and
    /// JSON contract.
    func grade(chinese: String, reference: String, attempt: String) async throws -> ProductionGrade {
        let systemPrompt = ProductionGradeShared.systemPrompt + ProductionGradeShared.jsonInstruction

        let promptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ec-gradeprompt-\(UUID().uuidString).txt")
        try systemPrompt.write(to: promptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        let command = Self.makeCommand(model: model, promptURL: promptURL)
        let stdin = ProductionGradeShared.userContent(
            chinese: chinese,
            reference: reference,
            attempt: attempt
        )
        let stdout = try await Self.runLoginShell(command: command, stdin: stdin)

        guard let data = stdout.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let resultText = envelope.result?.trimmed,
              !resultText.isEmpty else {
            throw ClaudeCLIError.emptyResponse
        }

        return try ProductionGradeShared.grade(fromJSONText: resultText, provider: providerLabel)
    }

    private struct Envelope: Decodable {
        let result: String?
    }

    /// CLI output isn't schema-constrained, so spell out the JSON contract.
    private static let jsonInstruction = """


    请只输出一个 JSON 对象，不要使用 markdown 代码块或任何额外文字。字段：\
    translatedText (字符串)、phonetic (字符串或 null)、explanations (字符串数组)、example (字符串或 null)。
    """

    static func makeCommand(model: String, promptURL: URL) -> String {
        // perl's alarm fires SIGALRM after N seconds; it survives exec, so the
        // claude process is killed if it hangs.
        "perl -e 'alarm \(Self.timeoutSeconds); exec @ARGV' "
            + "claude -p --output-format json"
            + " --safe-mode"
            + " --no-session-persistence"
            + " --permission-mode dontAsk"
            + " --tools ''"
            + " --strict-mcp-config"
            + " --mcp-config '{}'"
            + " --model \(shellSingleQuote(model))"
            + " --append-system-prompt-file \(shellSingleQuote(promptURL.path))"
    }

    static func isolatedWorkingDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EnglishCoachClaudeCLI", isDirectory: true)
    }

    private static func shellSingleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func runLoginShell(command: String, stdin: String) async throws -> String {
        let workingDirectory = isolatedWorkingDirectory()
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = workingDirectory

            let outPipe = Pipe()
            let errPipe = Pipe()
            let inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = inPipe

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                switch proc.terminationStatus {
                case 0:
                    continuation.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                case 142:
                    // 128 + SIGALRM(14): the perl alarm timeout fired.
                    continuation.resume(throwing: ClaudeCLIError.timedOut)
                case 127:
                    // command not found inside the login shell.
                    continuation.resume(throwing: ClaudeCLIError.binaryNotFound)
                default:
                    let message = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: ClaudeCLIError.nonZeroExit(proc.terminationStatus, message))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ClaudeCLIError.launchFailed(error.localizedDescription))
                return
            }

            if let data = stdin.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            inPipe.fileHandleForWriting.closeFile()
        }
    }
}
