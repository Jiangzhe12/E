func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

let items = DesktopPetActionMenuItem.defaultItems

expectEqual(
    items.map(\.title),
    ["快速翻译", "翻译剪贴板", "今日单词", "上次翻译", "打开主窗口", "退出"],
    "desktop pet action menu should replace the menu bar popover actions"
)
expectEqual(
    items.map(\.systemImage),
    ["text.magnifyingglass", "doc.on.clipboard", "text.book.closed", "clock.arrow.circlepath", "macwindow", "power"],
    "desktop pet action menu should expose stable icons"
)

let styleDescriptions = items.map { item -> String in
    guard let visualStyle = Mirror(reflecting: item).children.first(where: { $0.label == "visualStyle" })?.value else {
        fatalError("desktop pet action menu item should expose visualStyle for richer button presentation")
    }
    return String(describing: visualStyle)
}

expectEqual(
    Set(styleDescriptions).count >= 3,
    true,
    "desktop pet action menu should use varied visual styles instead of identical plain buttons"
)

let compactStyles = DesktopPetCompactButtonVisualStyle.dailyWordControls
expectEqual(
    compactStyles.map(\.id),
    ["speak", "primary", "secondary"],
    "daily word desktop pet controls should expose compact visual roles"
)
expectEqual(
    Set(compactStyles.map(\.description)).count,
    3,
    "daily word desktop pet compact controls should not use identical plain button styles"
)

let translationStyles = DesktopPetCompactButtonVisualStyle.translationControls
expectEqual(
    translationStyles.map(\.id),
    ["copy", "speak", "learn", "secondary"],
    "translation desktop pet controls should expose compact visual roles"
)
expectEqual(
    Set(translationStyles.map(\.description)).count,
    4,
    "translation desktop pet compact controls should use distinct visual styles"
)

print("DesktopPetActionMenuTests passed")
