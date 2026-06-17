import Foundation

/// Tracks which daily-word cards currently have their translation revealed.
///
/// A Set lets the user flip between words without losing reveal state for
/// anything they already peeked at. `toggle(for:)` drives a "show / hide again"
/// button in the UI — the flash-card pattern, not a one-way "reveal and it's
/// gone" flow.
struct DailyWordTranslationRevealState {
    private var revealedIDs: Set<String> = []

    mutating func toggle(for wordID: String) {
        if revealedIDs.contains(wordID) {
            revealedIDs.remove(wordID)
        } else {
            revealedIDs.insert(wordID)
        }
    }

    mutating func hide(for wordID: String) {
        revealedIDs.remove(wordID)
    }

    func isRevealed(for wordID: String) -> Bool {
        revealedIDs.contains(wordID)
    }
}
