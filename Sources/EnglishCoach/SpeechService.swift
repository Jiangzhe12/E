import AVFoundation
import Foundation

/// Wraps a single `AVSpeechSynthesizer` so the rest of the app can ask for
/// speech without each call site building its own utterance and worrying
/// about overlapping speech.
@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let defaultLanguageCode: String

    init(defaultLanguageCode: String = "en-US") {
        self.defaultLanguageCode = defaultLanguageCode
    }

    /// Read `text` aloud. If something is already being spoken, it's
    /// interrupted so repeated taps don't pile up overlapping audio.
    func speak(_ text: String, languageCode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode ?? defaultLanguageCode)
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
