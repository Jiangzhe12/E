import AppIntents
import Foundation

/// Exposed to Shortcuts.app / Siri / Spotlight via App Intents. Users can drag
/// this into a Shortcut, pass any English text in, and get the Chinese
/// translation back as a string they can route anywhere (clipboard, TTS,
/// another Shortcut step, ...).
///
/// Deliberately stateless: we instantiate a fresh `TranslationService` here
/// instead of talking to the running `AppModel`, so the Intent also works when
/// the app is not running (Shortcuts may launch us in the background).
struct TranslateIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译英文"
    static let description = IntentDescription(
        "用 Nova 把英文翻译成中文，返回结果字符串。可以拼接在其它 Shortcut 动作之间。"
    )

    /// Most Shortcut uses just want the translated text back — no need to
    /// open our window.
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "原文",
        description: "要翻译的英文句子或单词"
    )
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .result(value: "")
        }
        let service = TranslationService(enableOnlineFallback: true)
        let outcome = try await service.translate(cleaned)
        return .result(value: outcome.result.translatedText)
    }
}

/// Registers spoken phrases and a Shortcuts.app tile for `TranslateIntent`.
/// The `applicationName` placeholder gets replaced with whatever CFBundleName
/// resolves to at runtime.
struct NovaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateIntent(),
            phrases: [
                "用 \(.applicationName) 翻译",
                "Translate with \(.applicationName)"
            ],
            shortTitle: "翻译英文",
            systemImageName: "character.bubble"
        )
    }
}
