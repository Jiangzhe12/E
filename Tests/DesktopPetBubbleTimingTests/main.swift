import Foundation

func expectEqual(
    _ first: TimeInterval,
    _ second: TimeInterval,
    _ message: String,
    accuracy: TimeInterval = 0.001
) {
    guard abs(first - second) < accuracy else {
        fatalError(message)
    }
}

expectEqual(
    DesktopPetBubbleTiming.defaultAutoDismissSeconds,
    10,
    "translation and generic feedback bubbles should keep the existing 10 second auto-dismiss"
)
expectEqual(
    DesktopPetBubbleTiming.dailyWordFeedbackAutoAdvanceSeconds,
    1.2,
    "daily word completion feedback should advance after 1.2 seconds"
)

print("DesktopPetBubbleTimingTests passed")
