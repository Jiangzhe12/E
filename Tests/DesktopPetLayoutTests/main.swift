import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

func expectEqual(
    _ first: CGFloat,
    _ second: CGFloat,
    _ message: String,
    accuracy: CGFloat = 0.001
) {
    expect(abs(first - second) < accuracy, message)
}

let metrics = DesktopPetLayoutMetrics()

do {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let draggedIdleFrame = CGRect(origin: CGPoint(x: 530, y: 240), size: metrics.idlePanelSize)
    let anchor = DesktopPetLayout.mascotAnchor(
        in: draggedIdleFrame,
        placement: .aboveLeft,
        metrics: metrics
    )

    let layout = DesktopPetLayout.bubbleLayout(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics
    )
    let resolvedAnchor = DesktopPetLayout.mascotAnchor(
        in: layout.frame,
        placement: layout.placement,
        metrics: metrics
    )

    expectEqual(resolvedAnchor.x, anchor.x, "bubble expansion should preserve dragged mascot x")
    expectEqual(resolvedAnchor.y, anchor.y, "bubble expansion should preserve dragged mascot y")
}

do {
    let visible = CGRect(x: 0, y: 0, width: 900, height: 500)
    let anchor = CGPoint(x: 520, y: visible.maxY - metrics.mascotAnchorYOffset)

    let layout = DesktopPetLayout.bubbleLayout(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics
    )

    expect(layout.placement.vertical == .below, "bubble should appear below when above has no room")
    expect(layout.frame.maxY <= visible.maxY - metrics.screenMargin, "below bubble should fit visible top")
}

do {
    let visible = CGRect(x: 0, y: 0, width: 900, height: 700)
    let anchor = CGPoint(
        x: visible.minX + metrics.mascotTrailingInset,
        y: 220
    )

    let layout = DesktopPetLayout.bubbleLayout(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics
    )

    expect(layout.placement.horizontal == .right, "bubble should open right when mascot is near left edge")
    expect(layout.frame.minX >= visible.minX + metrics.screenMargin, "right bubble should fit visible left")
}

print("DesktopPetLayoutTests passed")
