import CoreGraphics

enum DesktopPetBubbleVerticalPlacement: Equatable {
    case above
    case below
}

enum DesktopPetBubbleHorizontalPlacement: Equatable {
    /// The bubble expands to the left side of the mascot.
    case left
    /// The bubble expands to the right side of the mascot.
    case right
}

struct DesktopPetBubblePlacement: Equatable {
    let vertical: DesktopPetBubbleVerticalPlacement
    let horizontal: DesktopPetBubbleHorizontalPlacement

    static let aboveLeft = DesktopPetBubblePlacement(vertical: .above, horizontal: .left)
    static let aboveRight = DesktopPetBubblePlacement(vertical: .above, horizontal: .right)
    static let belowLeft = DesktopPetBubblePlacement(vertical: .below, horizontal: .left)
    static let belowRight = DesktopPetBubblePlacement(vertical: .below, horizontal: .right)
}

struct DesktopPetLayoutMetrics {
    var idlePanelSize = CGSize(width: 148, height: 156)
    var bubblePanelSize = CGSize(width: 424, height: 432)
    var mascotTrailingInset: CGFloat = 72
    var mascotAnchorYOffset: CGFloat = 78
    var screenMargin: CGFloat = 8
}

struct DesktopPetPanelLayout {
    let frame: CGRect
    let placement: DesktopPetBubblePlacement

    var origin: CGPoint {
        frame.origin
    }
}

enum DesktopPetLayout {
    static func mascotAnchor(
        in frame: CGRect,
        placement: DesktopPetBubblePlacement,
        metrics: DesktopPetLayoutMetrics
    ) -> CGPoint {
        CGPoint(
            x: frame.minX + mascotAnchorXOffset(
                for: frame.size,
                placement: placement,
                metrics: metrics
            ),
            y: frame.minY + mascotAnchorYOffset(
                for: frame.size,
                placement: placement,
                metrics: metrics
            )
        )
    }

    static func idleFrame(
        for anchor: CGPoint,
        visibleFrame: CGRect,
        metrics: DesktopPetLayoutMetrics
    ) -> CGRect {
        let origin = clampedOrigin(
            desired: CGPoint(
                x: anchor.x - metrics.idlePanelSize.width / 2,
                y: anchor.y - metrics.mascotAnchorYOffset
            ),
            size: metrics.idlePanelSize,
            visibleFrame: visibleFrame,
            margin: metrics.screenMargin
        )
        return CGRect(origin: origin, size: metrics.idlePanelSize)
    }

    static func bubbleLayout(
        for anchor: CGPoint,
        visibleFrame: CGRect,
        metrics: DesktopPetLayoutMetrics
    ) -> DesktopPetPanelLayout {
        let verticalOptions = orderedVerticalOptions(
            for: anchor,
            visibleFrame: visibleFrame,
            metrics: metrics
        )
        let horizontalOptions = orderedHorizontalOptions(
            for: anchor,
            visibleFrame: visibleFrame,
            metrics: metrics
        )

        let candidates = verticalOptions.flatMap { vertical in
            horizontalOptions.map { horizontal in
                DesktopPetBubblePlacement(vertical: vertical, horizontal: horizontal)
            }
        }

        for placement in candidates {
            let frame = bubbleFrame(
                for: anchor,
                placement: placement,
                metrics: metrics
            )
            if frameFits(frame, in: visibleFrame, margin: metrics.screenMargin) {
                return DesktopPetPanelLayout(frame: frame, placement: placement)
            }
        }

        let fallbackPlacement = candidates.first ?? .aboveLeft
        let fallbackFrame = bubbleFrame(
            for: anchor,
            placement: fallbackPlacement,
            metrics: metrics
        )
        let clampedOrigin = clampedOrigin(
            desired: fallbackFrame.origin,
            size: fallbackFrame.size,
            visibleFrame: visibleFrame,
            margin: metrics.screenMargin
        )
        return DesktopPetPanelLayout(
            frame: CGRect(origin: clampedOrigin, size: fallbackFrame.size),
            placement: fallbackPlacement
        )
    }

    private static func bubbleFrame(
        for anchor: CGPoint,
        placement: DesktopPetBubblePlacement,
        metrics: DesktopPetLayoutMetrics
    ) -> CGRect {
        let size = metrics.bubblePanelSize
        let origin = CGPoint(
            x: anchor.x - mascotAnchorXOffset(
                for: size,
                placement: placement,
                metrics: metrics
            ),
            y: anchor.y - mascotAnchorYOffset(
                for: size,
                placement: placement,
                metrics: metrics
            )
        )
        return CGRect(origin: origin, size: size)
    }

    private static func mascotAnchorXOffset(
        for size: CGSize,
        placement: DesktopPetBubblePlacement,
        metrics: DesktopPetLayoutMetrics
    ) -> CGFloat {
        if size.width <= metrics.idlePanelSize.width + 1 {
            return size.width / 2
        }

        switch placement.horizontal {
        case .left:
            return size.width - metrics.mascotTrailingInset
        case .right:
            return metrics.mascotTrailingInset
        }
    }

    private static func mascotAnchorYOffset(
        for size: CGSize,
        placement: DesktopPetBubblePlacement,
        metrics: DesktopPetLayoutMetrics
    ) -> CGFloat {
        if size.height <= metrics.idlePanelSize.height + 1 {
            return metrics.mascotAnchorYOffset
        }

        switch placement.vertical {
        case .above:
            return metrics.mascotAnchorYOffset
        case .below:
            return size.height - metrics.mascotAnchorYOffset
        }
    }

    private static func orderedVerticalOptions(
        for anchor: CGPoint,
        visibleFrame: CGRect,
        metrics: DesktopPetLayoutMetrics
    ) -> [DesktopPetBubbleVerticalPlacement] {
        let spaceAbove = visibleFrame.maxY - metrics.screenMargin - anchor.y
        let spaceBelow = anchor.y - (visibleFrame.minY + metrics.screenMargin)
        let tallSideRequirement = metrics.bubblePanelSize.height - metrics.mascotAnchorYOffset
        let shortSideRequirement = metrics.mascotAnchorYOffset

        let aboveFits = spaceAbove >= tallSideRequirement
            && spaceBelow >= shortSideRequirement
        let belowFits = spaceBelow >= tallSideRequirement
            && spaceAbove >= shortSideRequirement

        if aboveFits {
            return [.above, .below]
        }
        if belowFits {
            return [.below, .above]
        }
        return spaceAbove >= spaceBelow ? [.above, .below] : [.below, .above]
    }

    private static func orderedHorizontalOptions(
        for anchor: CGPoint,
        visibleFrame: CGRect,
        metrics: DesktopPetLayoutMetrics
    ) -> [DesktopPetBubbleHorizontalPlacement] {
        let spaceLeft = anchor.x - (visibleFrame.minX + metrics.screenMargin)
        let spaceRight = visibleFrame.maxX - metrics.screenMargin - anchor.x
        let wideSideRequirement = metrics.bubblePanelSize.width - metrics.mascotTrailingInset
        let shortSideRequirement = metrics.mascotTrailingInset

        let leftFits = spaceLeft >= wideSideRequirement
            && spaceRight >= shortSideRequirement
        let rightFits = spaceRight >= wideSideRequirement
            && spaceLeft >= shortSideRequirement

        if leftFits {
            return [.left, .right]
        }
        if rightFits {
            return [.right, .left]
        }
        return spaceLeft >= spaceRight ? [.left, .right] : [.right, .left]
    }

    private static func frameFits(_ frame: CGRect, in visibleFrame: CGRect, margin: CGFloat) -> Bool {
        frame.minX >= visibleFrame.minX + margin
            && frame.maxX <= visibleFrame.maxX - margin
            && frame.minY >= visibleFrame.minY + margin
            && frame.maxY <= visibleFrame.maxY - margin
    }

    private static func clampedOrigin(
        desired: CGPoint,
        size: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat
    ) -> CGPoint {
        let maxX = visibleFrame.maxX - size.width - margin
        let maxY = visibleFrame.maxY - size.height - margin
        let minX = visibleFrame.minX + margin
        let minY = visibleFrame.minY + margin

        return CGPoint(
            x: clamp(desired.x, min: minX, max: max(maxX, minX)),
            y: clamp(desired.y, min: minY, max: max(maxY, minY))
        )
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }
}
