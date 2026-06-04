import Foundation

/// Compact presentation data for the desktop pet bubble. Keeping this separate
/// from SwiftUI makes the bubble rules easy to keep consistent across views.
struct DesktopPetBubbleContent {
    let originalText: String
    let translatedText: String
    let phonetic: String?
    let explanationBullets: [String]
    let metadata: String
    let provider: String

    init(result: TranslationResult, sourceAppName: String?) {
        originalText = result.originalText
        translatedText = result.translatedText
        phonetic = result.phonetic?.trimmed.isEmpty == false ? result.phonetic : nil
        explanationBullets = Array(result.explanations.prefix(2))
        provider = result.provider

        let cleanSource = sourceAppName?.trimmed ?? ""
        if cleanSource.isEmpty {
            metadata = result.direction.displayLabel
        } else {
            metadata = "\(result.direction.displayLabel) · \(cleanSource)"
        }
    }
}
