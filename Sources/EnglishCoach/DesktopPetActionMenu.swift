struct DesktopPetActionMenuVisualStyle: Equatable, CustomStringConvertible {
    let id: String
    let accentHex: String
    let fillHex: String
    let borderHex: String

    var description: String {
        "\(id):\(accentHex):\(fillHex):\(borderHex)"
    }
}

struct DesktopPetCompactButtonVisualStyle: Equatable, CustomStringConvertible {
    let id: String
    let accentHex: String
    let fillHex: String
    let borderHex: String

    var description: String {
        "\(id):\(accentHex):\(fillHex):\(borderHex)"
    }

    static let speak = DesktopPetCompactButtonVisualStyle(
        id: "speak",
        accentHex: "80F4FF",
        fillHex: "102C50",
        borderHex: "51E5FF"
    )
    static let copy = DesktopPetCompactButtonVisualStyle(
        id: "copy",
        accentHex: "8EEBFF",
        fillHex: "0F3057",
        borderHex: "54D8FF"
    )
    static let primary = DesktopPetCompactButtonVisualStyle(
        id: "primary",
        accentHex: "9FE7FF",
        fillHex: "123364",
        borderHex: "65D9FF"
    )
    static let learn = DesktopPetCompactButtonVisualStyle(
        id: "learn",
        accentHex: "8CFFC0",
        fillHex: "12363A",
        borderHex: "63E6A6"
    )
    static let secondary = DesktopPetCompactButtonVisualStyle(
        id: "secondary",
        accentHex: "B9A4FF",
        fillHex: "221E50",
        borderHex: "9B7DFF"
    )

    static let dailyWordControls: [DesktopPetCompactButtonVisualStyle] = [
        .speak,
        .primary,
        .secondary
    ]

    static let translationControls: [DesktopPetCompactButtonVisualStyle] = [
        .copy,
        .speak,
        .learn,
        .secondary
    ]
}

struct DesktopPetActionMenuItem: Identifiable, Equatable {
    enum Action: String {
        case quickTranslate
        case translateClipboard
        case dailyWord
        case quickAddTodo
        case showTodos
        case lastTranslation
        case openMainWindow
        case quit
    }

    let action: Action
    let title: String
    let systemImage: String
    let visualStyle: DesktopPetActionMenuVisualStyle

    var id: String { action.rawValue }

    static let defaultItems: [DesktopPetActionMenuItem] = [
        DesktopPetActionMenuItem(
            action: .quickTranslate,
            title: "快速翻译",
            systemImage: "text.magnifyingglass",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "aqua", accentHex: "7AEEF7", fillHex: "0E2B52", borderHex: "50E8FF")
        ),
        DesktopPetActionMenuItem(
            action: .translateClipboard,
            title: "翻译剪贴板",
            systemImage: "doc.on.clipboard",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "violet", accentHex: "B39CFF", fillHex: "1A2455", borderHex: "8A7CFF")
        ),
        DesktopPetActionMenuItem(
            action: .dailyWord,
            title: "今日单词",
            systemImage: "text.book.closed",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "mint", accentHex: "7CFFD0", fillHex: "102D3C", borderHex: "56E2BC")
        ),
        DesktopPetActionMenuItem(
            action: .quickAddTodo,
            title: "快速记待办",
            systemImage: "plus.rectangle.on.rectangle",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "todoAdd", accentHex: "FFD08A", fillHex: "322410", borderHex: "F2B84B")
        ),
        DesktopPetActionMenuItem(
            action: .showTodos,
            title: "今日待办",
            systemImage: "checklist",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "todoList", accentHex: "8CFFC0", fillHex: "12363A", borderHex: "63E6A6")
        ),
        DesktopPetActionMenuItem(
            action: .lastTranslation,
            title: "上次翻译",
            systemImage: "clock.arrow.circlepath",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "amber", accentHex: "FFD36E", fillHex: "322845", borderHex: "F2B84B")
        ),
        DesktopPetActionMenuItem(
            action: .openMainWindow,
            title: "打开主窗口",
            systemImage: "macwindow",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "sky", accentHex: "8BCBFF", fillHex: "112B4E", borderHex: "6CB6FF")
        ),
        DesktopPetActionMenuItem(
            action: .quit,
            title: "退出",
            systemImage: "power",
            visualStyle: DesktopPetActionMenuVisualStyle(id: "coral", accentHex: "FF8585", fillHex: "351A31", borderHex: "FF6B72")
        )
    ]
}
