import SwiftUI

/// Visual skin for a translation result body. Lets the desktop-pet bubble keep its
/// always-dark neon identity while the quick-translate popover uses system colors —
/// both sharing one layout so the same translation never looks like two different apps.
struct TranslationResultStyle {
    var original: Color
    var translated: Color
    var phonetic: Color
    var explanation: Color

    /// Desktop-pet bubble (always dark neon skin).
    static let petBubble = TranslationResultStyle(
        original: PetPalette.subtitle,
        translated: PetPalette.ink,
        phonetic: PetPalette.violet,
        explanation: PetPalette.bullet
    )

    /// Light system-style panel (quick-translate popover).
    static let panel = TranslationResultStyle(
        original: .secondary,
        translated: AppColor.ink,
        phonetic: .secondary,
        explanation: .secondary
    )
}

/// Shared layout for a translation result: original → translated → phonetic → explanations.
/// Containers (pet bubble / quick-translate popover) own their own header and action row and
/// just supply the data + a ``TranslationResultStyle``; an optional trailing accessory rides
/// on the original line (the popover uses it for the direction badge).
struct TranslationResultBody<Trailing: View>: View {
    let original: String
    let translated: String
    let phonetic: String?
    let explanations: [String]
    var originalLineLimit: Int? = 1
    let style: TranslationResultStyle
    @ViewBuilder var originalTrailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(original)
                    .font(.caption)
                    .foregroundStyle(style.original)
                    .lineLimit(originalLineLimit)
                originalTrailing()
            }

            Text(translated)
                .font(.title3.weight(.semibold))
                .foregroundStyle(style.translated)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(.caption.monospaced())
                    .foregroundStyle(style.phonetic)
                    .lineLimit(1)
            }

            if !explanations.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(explanations.enumerated()), id: \.offset) { _, explanation in
                        Text("· \(explanation)")
                            .font(.caption)
                            .foregroundStyle(style.explanation)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

extension TranslationResultBody where Trailing == EmptyView {
    init(
        original: String,
        translated: String,
        phonetic: String?,
        explanations: [String],
        originalLineLimit: Int? = 1,
        style: TranslationResultStyle
    ) {
        self.init(
            original: original,
            translated: translated,
            phonetic: phonetic,
            explanations: explanations,
            originalLineLimit: originalLineLimit,
            style: style,
            originalTrailing: { EmptyView() }
        )
    }
}
