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

do {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let expectedVisibleWidth: CGFloat = 104
    let anchor = CGPoint(
        x: visible.maxX - metrics.idlePanelSize.width / 2 + 12,
        y: 240
    )

    let frame = DesktopPetLayout.idleFrame(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics
    )

    expectEqual(frame.minX, visible.maxX - expectedVisibleWidth, "idle pet should cling to the right screen edge")
    expect(frame.maxX > visible.maxX, "right-clinging idle pet should partially hide off-screen")
}

do {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let expectedVisibleWidth: CGFloat = 104
    let anchor = CGPoint(
        x: visible.minX + metrics.idlePanelSize.width / 2 - 12,
        y: 240
    )

    let frame = DesktopPetLayout.idleFrame(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics
    )

    expectEqual(frame.maxX, visible.minX + expectedVisibleWidth, "idle pet should cling to the left screen edge")
    expect(frame.minX < visible.minX, "left-clinging idle pet should partially hide off-screen")
}

do {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let defaultInset: CGFloat = 22
    let anchor = CGPoint(
        x: visible.maxX - metrics.idlePanelSize.width / 2 - defaultInset,
        y: 240
    )

    let frame = DesktopPetLayout.idleFrame(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics
    )

    expectEqual(frame.maxX, visible.maxX - defaultInset, "default right-side pet placement should not start edge-clinging")
    expect(frame.minX >= visible.minX, "default right-side pet placement should remain fully visible")
}

do {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let idleFrame = DesktopPetLayout.idleFrame(
        for: CGPoint(x: visible.maxX - metrics.idlePanelSize.width / 2 + 12, y: 240),
        visibleFrame: visible,
        metrics: metrics
    )
    let anchor = DesktopPetLayout.mascotAnchor(
        in: idleFrame,
        placement: .aboveLeft,
        metrics: metrics
    )

    let layout = DesktopPetLayout.bubbleLayout(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics,
        edgeAttachment: .right
    )
    let resolvedAnchor = DesktopPetLayout.mascotAnchor(
        in: layout.frame,
        placement: layout.placement,
        metrics: metrics
    )

    expectEqual(resolvedAnchor.x, anchor.x, "right-clinging bubble should not pull the mascot back onscreen")
    expect(layout.frame.maxX > visible.maxX, "right-clinging bubble panel should keep the mascot side offscreen")
    expect(layout.placement.horizontal == .left, "right-clinging bubble should open inward to the left")
}

do {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let idleFrame = DesktopPetLayout.idleFrame(
        for: CGPoint(x: visible.minX + metrics.idlePanelSize.width / 2 - 12, y: 240),
        visibleFrame: visible,
        metrics: metrics
    )
    let anchor = DesktopPetLayout.mascotAnchor(
        in: idleFrame,
        placement: .aboveLeft,
        metrics: metrics
    )

    let layout = DesktopPetLayout.bubbleLayout(
        for: anchor,
        visibleFrame: visible,
        metrics: metrics,
        edgeAttachment: .left
    )
    let resolvedAnchor = DesktopPetLayout.mascotAnchor(
        in: layout.frame,
        placement: layout.placement,
        metrics: metrics
    )

    expectEqual(resolvedAnchor.x, anchor.x, "left-clinging bubble should not pull the mascot back onscreen")
    expect(layout.frame.minX < visible.minX, "left-clinging bubble panel should keep the mascot side offscreen")
    expect(layout.placement.horizontal == .right, "left-clinging bubble should open inward to the right")
}

print("DesktopPetLayoutTests passed")
