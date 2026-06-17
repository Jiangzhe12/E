import AppKit
import SwiftUI

/// One row in the desktop-pet "today's todos" bubble.
struct DesktopPetTodoRow: Identifiable, Equatable {
    let id: String
    let title: String
    let dueLabel: String?
}

enum DesktopPetBubble {
    case none
    case actionMenu
    case translating(String)
    case translation(result: TranslationResult, sourceAppName: String?)
    case dailyWordInvite(DesktopWordCard)
    case dailyWordMeaning(DesktopWordCard)
    case dailyWordCompletion(message: String)
    case feedback(title: String, message: String)
    case todoList(rows: [DesktopPetTodoRow], openCount: Int)
    case todoForm
}

enum DesktopPetMood {
    case idle
    case translating
    case result
    case learning
    case success
}

@MainActor
final class DesktopPetPresentationState: ObservableObject {
    @Published var bubble: DesktopPetBubble = .none
    @Published var bubblePlacement: DesktopPetBubblePlacement = .aboveLeft
    @Published var edgeAttachment: DesktopPetEdgeAttachment = .none
    @Published private(set) var bubbleID = UUID()

    var content: DesktopPetBubbleContent? {
        guard case let .translation(result, sourceAppName) = bubble else { return nil }
        return DesktopPetBubbleContent(result: result, sourceAppName: sourceAppName)
    }

    var hasBubble: Bool {
        if case .none = bubble {
            return false
        }
        return true
    }

    var mood: DesktopPetMood {
        switch bubble {
        case .none:
            return .idle
        case .actionMenu:
            return .result
        case .translating:
            return .translating
        case .translation:
            return .result
        case .dailyWordInvite, .dailyWordMeaning:
            return .learning
        case .dailyWordCompletion:
            return .success
        case .feedback:
            return .success
        case .todoList:
            return .learning
        case .todoForm:
            return .learning
        }
    }

    func show(result: TranslationResult, sourceAppName: String?) {
        bubble = .translation(result: result, sourceAppName: sourceAppName)
        bubbleID = UUID()
    }

    func showActionMenu() {
        bubble = .actionMenu
        bubbleID = UUID()
    }

    func setBubblePlacement(_ placement: DesktopPetBubblePlacement) {
        bubblePlacement = placement
    }

    func setEdgeAttachment(_ attachment: DesktopPetEdgeAttachment) {
        edgeAttachment = attachment
    }

    func showTranslating(_ text: String) {
        bubble = .translating(text)
        bubbleID = UUID()
    }

    func showDailyWordInvite(_ card: DesktopWordCard) {
        bubble = .dailyWordInvite(card)
        bubbleID = UUID()
    }

    func showDailyWordMeaning(_ card: DesktopWordCard) {
        bubble = .dailyWordMeaning(card)
        bubbleID = UUID()
    }

    func showDailyWordCompletion(message: String) {
        bubble = .dailyWordCompletion(message: message)
        bubbleID = UUID()
    }

    func showFeedback(title: String, message: String) {
        bubble = .feedback(title: title, message: message)
        bubbleID = UUID()
    }

    func showTodos(rows: [DesktopPetTodoRow], openCount: Int) {
        bubble = .todoList(rows: rows, openCount: openCount)
        bubbleID = UUID()
    }

    func showTodoForm() {
        bubble = .todoForm
        bubbleID = UUID()
    }

    func clearBubble() {
        bubble = .none
        bubbleID = UUID()
    }
}

struct DesktopPetTranslationView: View {
    @ObservedObject var state: DesktopPetPresentationState
    let onCopy: (TranslationResult) -> Void
    let onOpenMainWindow: () -> Void
    let onQuickTranslate: () -> Void
    let onTranslateClipboard: () -> Void
    let onShowDailyWord: () -> Void
    let onShowLastTranslation: () -> Void
    let onQuitApp: () -> Void
    let onSpeak: (TranslationResult) -> Void
    let onAddToLearning: (TranslationResult) -> Void
    let onCloseBubble: () -> Void
    let onPetTap: () -> Void
    let onPetSecondaryTap: () -> Void
    let onShowDailyWordMeaning: (DesktopWordCard) -> Void
    let onDailyWordComplete: (DesktopWordCard) -> Void
    let onDailyWordPractice: (DesktopWordCard) -> Void
    let onStartNextDailyWordGroup: () -> Void
    let onSpeakDailyWord: (DesktopWordCard) -> Void
    let onQuickAddTodo: () -> Void
    let onShowTodos: () -> Void
    let onCompleteTodo: (String) -> Void
    let onOpenTodoList: () -> Void
    let onSubmitNewTodo: (NewTodoDraft) -> Void

    @State private var isFloating = false
    @State private var isHovering = false

    private var panelSize: CGSize {
        !state.hasBubble
            ? CGSize(width: 148, height: 156)
            : CGSize(width: 424, height: 432)
    }

    private var contentAlignment: Alignment {
        guard state.hasBubble else { return .bottom }

        switch (state.bubblePlacement.vertical, state.bubblePlacement.horizontal) {
        case (.above, .left):
            return .bottomTrailing
        case (.above, .right):
            return .bottomLeading
        case (.below, .left):
            return .topTrailing
        case (.below, .right):
            return .topLeading
        }
    }

    private var stackAlignment: HorizontalAlignment {
        guard state.hasBubble else { return .center }
        return state.bubblePlacement.horizontal == .left ? .trailing : .leading
    }

    private var bubbleTailOffset: CGFloat {
        state.bubblePlacement.horizontal == .left ? 106 : -106
    }

    private var bubbleTailPosition: DesktopPetBubbleTailPosition {
        state.bubblePlacement.vertical == .below ? .top : .bottom
    }

    private var bubbleLayerEdgeOffset: CGFloat {
        let metrics = DesktopPetLayoutMetrics()
        let hiddenWidth = metrics.idlePanelSize.width - metrics.edgeClingVisibleWidth
        switch state.edgeAttachment {
        case .left:
            return hiddenWidth
        case .right:
            return -hiddenWidth
        case .none:
            return 0
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: stackAlignment, spacing: 0) {
                if state.hasBubble && state.bubblePlacement.vertical == .below {
                    mascotLayer
                    bubbleLayer
                } else {
                    bubbleLayer
                    mascotLayer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .bottom)
        .background(Color.clear)
        .onAppear {
            isFloating = true
        }
        .onExitCommand(perform: onCloseBubble)
    }

    @ViewBuilder
    private var bubbleLayer: some View {
        Group {
            switch state.bubble {
            case .none:
                EmptyView()
            case .actionMenu:
                DesktopPetActionMenuBubbleView(
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onQuickTranslate: onQuickTranslate,
                    onTranslateClipboard: onTranslateClipboard,
                    onShowDailyWord: onShowDailyWord,
                    onShowLastTranslation: onShowLastTranslation,
                    onOpenMainWindow: onOpenMainWindow,
                    onQuitApp: onQuitApp,
                    onQuickAddTodo: onQuickAddTodo,
                    onShowTodos: onShowTodos,
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case let .translating(text):
                DesktopPetTranslatingBubbleView(
                    text: text,
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case let .translation(result, _):
                if let content = state.content {
                    DesktopPetTranslationBubbleView(
                        content: content,
                        result: result,
                        tailOffset: bubbleTailOffset,
                        tailPosition: bubbleTailPosition,
                        onCopy: onCopy,
                        onOpenMainWindow: onOpenMainWindow,
                        onSpeak: onSpeak,
                        onAddToLearning: onAddToLearning,
                        onCloseBubble: onCloseBubble
                    )
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                }
            case let .dailyWordInvite(card):
            DesktopPetDailyWordInviteBubbleView(
                card: card,
                tailOffset: bubbleTailOffset,
                tailPosition: bubbleTailPosition,
                onReveal: { onShowDailyWordMeaning(card) },
                onSpeak: { onSpeakDailyWord(card) },
                onCloseBubble: onCloseBubble
            )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case let .dailyWordMeaning(card):
                DesktopPetDailyWordMeaningBubbleView(
                    card: card,
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onComplete: { onDailyWordComplete(card) },
                    onPractice: { onDailyWordPractice(card) },
                    onSpeak: { onSpeakDailyWord(card) },
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case let .dailyWordCompletion(message):
                DesktopPetDailyWordCompletionBubbleView(
                    message: message,
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onStartNextGroup: onStartNextDailyWordGroup,
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case let .feedback(title, message):
                DesktopPetFeedbackBubbleView(
                    title: title,
                    message: message,
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case let .todoList(rows, openCount):
                DesktopPetTodoListBubbleView(
                    rows: rows,
                    openCount: openCount,
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onCompleteTodo: onCompleteTodo,
                    onOpenList: onOpenTodoList,
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            case .todoForm:
                DesktopPetTodoFormBubbleView(
                    tailOffset: bubbleTailOffset,
                    tailPosition: bubbleTailPosition,
                    onSubmit: onSubmitNewTodo,
                    onCloseBubble: onCloseBubble
                )
                .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
            }
        }
        .offset(x: bubbleLayerEdgeOffset)
    }

    private var mascotLayer: some View {
        DesktopPetMascotView(
            isShowingBubble: state.hasBubble,
            mood: state.mood,
            isHovering: isHovering,
            edgeAttachment: state.edgeAttachment
        )
            .offset(y: isFloating ? -4 : 2)
            .animation(
                .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                value: isFloating
            )
            .scaleEffect(isHovering ? 1.04 : 1.0, anchor: .bottom)
            .animation(.spring(response: 0.24, dampingFraction: 0.70), value: isHovering)
            .contentShape(Rectangle())
            .overlay(
                PetMouseCatcher(
                    toolTip: "左键：功能菜单 · 右键：上次翻译",
                    onLeftClick: onPetTap,
                    onRightClick: onPetSecondaryTap,
                    onHoverChange: { isHovering = $0 }
                )
            )
    }
}

/// AppKit-backed mouse layer for the mascot. Owns left-click (tap), right-click,
/// drag-to-move-the-panel, and hover in one place so SwiftUI gesture recognizers
/// and AppKit right-click handling don't fight over the same view.
private struct PetMouseCatcher: NSViewRepresentable {
    let toolTip: String
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MouseView()
        view.toolTip = toolTip
        view.apply(onLeftClick: onLeftClick, onRightClick: onRightClick, onHoverChange: onHoverChange)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MouseView else { return }
        view.toolTip = toolTip
        view.apply(onLeftClick: onLeftClick, onRightClick: onRightClick, onHoverChange: onHoverChange)
    }

    final class MouseView: NSView {
        private var onLeftClick: (() -> Void)?
        private var onRightClick: (() -> Void)?
        private var onHoverChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?
        private var didDrag = false

        func apply(
            onLeftClick: @escaping () -> Void,
            onRightClick: @escaping () -> Void,
            onHoverChange: @escaping (Bool) -> Void
        ) {
            self.onLeftClick = onLeftClick
            self.onRightClick = onRightClick
            self.onHoverChange = onHoverChange
        }

        override func mouseDown(with event: NSEvent) {
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            didDrag = true
            // Let the user reposition the desktop pet by dragging it.
            window?.performDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            if !didDrag {
                onLeftClick?()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChange?(false)
        }
    }
}

private enum DesktopPetBubbleTailPosition {
    case top
    case bottom
}

private struct DesktopPetTranslationBubbleView: View {
    let content: DesktopPetBubbleContent
    let result: TranslationResult
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onCopy: (TranslationResult) -> Void
    let onOpenMainWindow: () -> Void
    let onSpeak: (TranslationResult) -> Void
    let onAddToLearning: (TranslationResult) -> Void
    let onCloseBubble: () -> Void

    /// "加入生词本" only makes sense for a single English word.
    private var canAddToLearning: Bool {
        let trimmed = result.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        guard !trimmed.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else { return false }
        return trimmed.unicodeScalars.contains { $0.value < 128 && CharacterSet.letters.contains($0) }
            && trimmed.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'"
            }
    }

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .foregroundStyle(Color(red: 0.42, green: 0.94, blue: 1.0))

                    Text(content.metadata)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.58, green: 0.96, blue: 1.0))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: onCloseBubble) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.64, green: 0.78, blue: 0.95))
                    .help("关闭气泡")
                    .bubbleClickableHover()
                }

                Text(content.originalText)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.62, green: 0.75, blue: 0.95))
                    .lineLimit(1)

                Text(content.translatedText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let phonetic = content.phonetic {
                    Text(phonetic)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(red: 0.65, green: 0.55, blue: 1.0))
                        .lineLimit(1)
                }

                if !content.explanationBullets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(content.explanationBullets.enumerated()), id: \.offset) { _, explanation in
                            Text("· \(explanation)")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.72, green: 0.82, blue: 0.98))
                                .lineLimit(2)
                        }
                    }
                }

                HStack(spacing: 8) {
                    DesktopPetCompactButton(
                        title: "复制",
                        systemImage: "doc.on.doc.fill",
                        visualStyle: .copy,
                        action: { onCopy(result) }
                    )

                    DesktopPetCompactButton(
                        systemImage: "speaker.wave.2.fill",
                        visualStyle: .speak,
                        help: "朗读原文",
                        action: { onSpeak(result) }
                    )

                    if canAddToLearning {
                        DesktopPetCompactButton(
                            systemImage: "text.badge.plus",
                            visualStyle: .learn,
                            help: "加入生词本",
                            action: { onAddToLearning(result) }
                        )
                    }

                    DesktopPetCompactButton(
                        title: "展开",
                        systemImage: "rectangle.arrowtriangle.2.outward",
                        visualStyle: .secondary,
                        action: onOpenMainWindow
                    )

                    Spacer()

                    Text(content.provider)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.55, green: 0.67, blue: 0.92))
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct DesktopPetActionMenuBubbleView: View {
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onQuickTranslate: () -> Void
    let onTranslateClipboard: () -> Void
    let onShowDailyWord: () -> Void
    let onShowLastTranslation: () -> Void
    let onOpenMainWindow: () -> Void
    let onQuitApp: () -> Void
    let onQuickAddTodo: () -> Void
    let onShowTodos: () -> Void
    let onCloseBubble: () -> Void

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 10) {
                DesktopPetBubbleHeader(
                    icon: "sparkles",
                    title: "EnglishCoach",
                    onCloseBubble: onCloseBubble
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(DesktopPetActionMenuItem.defaultItems) { item in
                        DesktopPetActionMenuButton(item: item) {
                            perform(item.action)
                        }
                    }
                }
            }
        }
    }

    private func perform(_ action: DesktopPetActionMenuItem.Action) {
        switch action {
        case .quickTranslate:
            onQuickTranslate()
        case .translateClipboard:
            onTranslateClipboard()
        case .dailyWord:
            onShowDailyWord()
        case .quickAddTodo:
            onQuickAddTodo()
        case .showTodos:
            onShowTodos()
        case .lastTranslation:
            onShowLastTranslation()
        case .openMainWindow:
            onOpenMainWindow()
        case .quit:
            onQuitApp()
        }
    }
}

private struct DesktopPetActionMenuButton: View {
    let item: DesktopPetActionMenuItem
    let action: () -> Void
    @State private var isHovering = false

    private var style: DesktopPetActionMenuVisualStyle {
        item.visualStyle
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    style.accentColor.opacity(0.25),
                                    style.accentColor.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(style.accentColor.opacity(0.42), lineWidth: 1)
                        )

                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(style.accentColor)
                }
                .frame(width: 26, height: 26)

                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.action == .quit
                        ? Color(red: 1.0, green: 0.83, blue: 0.84)
                        : Color(red: 0.90, green: 0.99, blue: 1.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .padding(.horizontal, 9)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                style.fillColor.opacity(isHovering ? 0.96 : 0.80),
                                Color(red: 0.04, green: 0.08, blue: 0.24).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(style.borderColor.opacity(isHovering ? 0.78 : 0.34), lineWidth: 1)
                    )
                    .shadow(color: style.accentColor.opacity(isHovering ? 0.24 : 0.10), radius: isHovering ? 8 : 4, x: 0, y: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(DesktopPetActionMenuButtonStyle(isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

private struct DesktopPetActionMenuButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : (isHovering ? 1.025 : 1.0))
            .brightness(configuration.isPressed ? -0.03 : (isHovering ? 0.05 : 0))
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct DesktopPetCompactButton: View {
    var title: String?
    let systemImage: String
    let visualStyle: DesktopPetCompactButtonVisualStyle
    var help: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: title == nil ? 0 : 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(visualStyle.accentColor)
                    .frame(width: title == nil ? 22 : 18, height: 18)

                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.92, green: 0.99, blue: 1.0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(minWidth: title == nil ? 42 : 76, minHeight: 30)
            .padding(.horizontal, title == nil ? 4 : 10)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                visualStyle.fillColor.opacity(isHovering ? 0.98 : 0.84),
                                Color(red: 0.04, green: 0.08, blue: 0.24).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(visualStyle.borderColor.opacity(isHovering ? 0.82 : 0.42), lineWidth: 1)
                    )
                    .shadow(color: visualStyle.accentColor.opacity(isHovering ? 0.28 : 0.12), radius: isHovering ? 7 : 4, x: 0, y: 3)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(DesktopPetCompactButtonPressStyle(isHovering: isHovering))
        .help(help ?? title ?? "")
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

private struct DesktopPetCompactButtonPressStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovering ? 1.04 : 1.0))
            .brightness(configuration.isPressed ? -0.04 : (isHovering ? 0.06 : 0))
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private extension DesktopPetActionMenuVisualStyle {
    var accentColor: Color {
        Color(desktopPetHex: accentHex)
    }

    var fillColor: Color {
        Color(desktopPetHex: fillHex)
    }

    var borderColor: Color {
        Color(desktopPetHex: borderHex)
    }
}

private extension DesktopPetCompactButtonVisualStyle {
    var accentColor: Color {
        Color(desktopPetHex: accentHex)
    }

    var fillColor: Color {
        Color(desktopPetHex: fillHex)
    }

    var borderColor: Color {
        Color(desktopPetHex: borderHex)
    }
}

private extension Color {
    init(desktopPetHex hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

private struct DesktopPetTranslatingBubbleView: View {
    let text: String
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onCloseBubble: () -> Void

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 10) {
                DesktopPetBubbleHeader(
                    icon: "sparkles",
                    title: "翻译中",
                    onCloseBubble: onCloseBubble
                )

                Text(text)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.62, green: 0.75, blue: 0.95))
                    .lineLimit(1)

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Rectangle()
                            .fill(index == 1
                                ? Color(red: 0.62, green: 0.46, blue: 1.0)
                                : Color(red: 0.42, green: 0.94, blue: 1.0)
                            )
                            .frame(width: 8, height: 8)
                    }
                    Text("正在解析选中文本")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                }
            }
        }
    }
}

private struct DesktopPetDailyWordInviteBubbleView: View {
    let card: DesktopWordCard
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onReveal: () -> Void
    let onSpeak: () -> Void
    let onCloseBubble: () -> Void

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 10) {
                DesktopPetBubbleHeader(
                    icon: "tag.fill",
                    title: card.isReview ? "复习词" : "今日词",
                    trailingBadge: card.progressBadgeText,
                    onCloseBubble: onCloseBubble
                )

                Text(card.word)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let phonetic = card.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(red: 0.65, green: 0.55, blue: 1.0))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    DesktopPetCompactButton(
                        systemImage: "speaker.wave.2.fill",
                        visualStyle: .speak,
                        help: "朗读单词",
                        action: onSpeak
                    )

                    DesktopPetCompactButton(
                        title: "看释义",
                        systemImage: "eye.fill",
                        visualStyle: .primary,
                        action: onReveal
                    )
                }
            }
        }
    }
}

private struct DesktopPetDailyWordMeaningBubbleView: View {
    let card: DesktopWordCard
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onComplete: () -> Void
    let onPractice: () -> Void
    let onSpeak: () -> Void
    let onCloseBubble: () -> Void

    private var primaryActionTitle: String {
        card.isReview ? "还记得" : "记住了"
    }

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 9) {
                DesktopPetBubbleHeader(
                    icon: "character.book.closed.fill",
                    title: card.word,
                    trailingBadge: card.progressBadgeText,
                    onCloseBubble: onCloseBubble
                )

                if let phonetic = card.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(red: 0.65, green: 0.55, blue: 1.0))
                        .lineLimit(1)
                }

                Text(card.meaning)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.explanation)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.72, green: 0.82, blue: 0.98))
                    .lineLimit(2)

                Text(card.example)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.62, green: 0.75, blue: 0.95))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    DesktopPetCompactButton(
                        systemImage: "speaker.wave.2.fill",
                        visualStyle: .speak,
                        help: "朗读",
                        action: onSpeak
                    )

                    DesktopPetCompactButton(
                        title: primaryActionTitle,
                        systemImage: "checkmark.seal.fill",
                        visualStyle: .primary,
                        action: onComplete
                    )

                    DesktopPetCompactButton(
                        title: "不熟悉",
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                        visualStyle: .secondary,
                        action: onPractice
                    )
                }
            }
        }
    }
}

private struct DesktopPetDailyWordCompletionBubbleView: View {
    let message: String
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onStartNextGroup: () -> Void
    let onCloseBubble: () -> Void

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 10) {
                DesktopPetBubbleHeader(
                    icon: "checkmark.seal.fill",
                    title: "今日已完成",
                    onCloseBubble: onCloseBubble
                )

                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Button {
                        onStartNextGroup()
                    } label: {
                        Label("学习下一组", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color(red: 0.18, green: 0.66, blue: 0.95))
                    .bubbleClickableHover()

                    Button("明天继续", action: onCloseBubble)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(Color(red: 0.52, green: 0.46, blue: 0.95))
                        .bubbleClickableHover()
                }
            }
        }
    }
}

private struct DesktopPetFeedbackBubbleView: View {
    let title: String
    let message: String
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onCloseBubble: () -> Void

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 9) {
                DesktopPetBubbleHeader(
                    icon: "sparkle",
                    title: title,
                    onCloseBubble: onCloseBubble
                )

                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                    .lineLimit(2)
            }
        }
    }
}

private struct DesktopPetTodoListBubbleView: View {
    let rows: [DesktopPetTodoRow]
    let openCount: Int
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onCompleteTodo: (String) -> Void
    let onOpenList: () -> Void
    let onCloseBubble: () -> Void

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 9) {
                DesktopPetBubbleHeader(
                    icon: "checklist",
                    title: "今日待办",
                    trailingBadge: "\(openCount) 项",
                    onCloseBubble: onCloseBubble
                )

                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color(red: 0.90, green: 0.99, blue: 1.0))
                                .lineLimit(1)
                            if let dueLabel = row.dueLabel {
                                Text(dueLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.55))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        DesktopPetCompactButton(
                            systemImage: "checkmark.circle.fill",
                            visualStyle: .learn,
                            help: "标记完成",
                            action: { onCompleteTodo(row.id) }
                        )
                    }
                }

                if openCount > rows.count {
                    Text("还有 \(openCount - rows.count) 项未显示")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.62, green: 0.75, blue: 0.95))
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    DesktopPetCompactButton(
                        title: "打开列表",
                        systemImage: "macwindow",
                        visualStyle: .primary,
                        action: onOpenList
                    )
                }
            }
        }
    }
}

private struct DesktopPetTodoFormBubbleView: View {
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    let onSubmit: (NewTodoDraft) -> Void
    let onCloseBubble: () -> Void

    @State private var title = ""
    @State private var category: TodoCategory = .feature
    @State private var priority: TodoPriority = .medium
    @State private var dueKey: String?
    @State private var note = ""
    @FocusState private var titleFocused: Bool

    private var todayKey: String { todoDayKey(for: Date()) }
    private var tomorrowKey: String {
        todoDayKey(for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
    }
    private var fridayKey: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let add = (6 - calendar.component(.weekday, from: today) + 7) % 7
        return todoDayKey(for: calendar.date(byAdding: .day, value: add, to: today) ?? today)
    }

    private let lightText = Color(red: 0.92, green: 0.99, blue: 1.0)
    private let subText = Color(red: 0.72, green: 0.82, blue: 0.98)
    private let accent = Color(red: 0.42, green: 0.94, blue: 1.0)

    var body: some View {
        DesktopPetBubbleShell(tailOffset: tailOffset, tailPosition: tailPosition) {
            VStack(alignment: .leading, spacing: 9) {
                DesktopPetBubbleHeader(icon: "plus.circle", title: "新建待办", onCloseBubble: onCloseBubble)

                darkField("待办标题", text: $title)
                    .focused($titleFocused)
                    .onSubmit(submit)

                labeledRow("分类") {
                    ForEach(TodoCategory.allCases) { item in
                        chip(item.title, selected: category == item) { category = item }
                    }
                }
                labeledRow("优先级") {
                    ForEach(TodoPriority.allCases) { item in
                        chip(item.title, selected: priority == item) { priority = item }
                    }
                }

                labeledRow("截止") {
                    chip("今天", selected: dueKey == todayKey) { dueKey = dueKey == todayKey ? nil : todayKey }
                    chip("明天", selected: dueKey == tomorrowKey) { dueKey = dueKey == tomorrowKey ? nil : tomorrowKey }
                    chip("周五", selected: dueKey == fridayKey) { dueKey = dueKey == fridayKey ? nil : fridayKey }
                    if dueKey != nil {
                        Button { dueKey = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(subText)
                        }
                        .buttonStyle(.plain)
                    }
                }

                darkField("备注（可选）", text: $note)

                HStack {
                    Spacer(minLength: 0)
                    DesktopPetCompactButton(
                        title: "添加",
                        systemImage: "checkmark.circle.fill",
                        visualStyle: .learn,
                        action: submit
                    )
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    @ViewBuilder
    private func labeledRow<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(subText).frame(width: 34, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func darkField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.callout)
            .foregroundStyle(lightText)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.04, green: 0.09, blue: 0.26).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(accent.opacity(0.30), lineWidth: 1))
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color(red: 0.04, green: 0.08, blue: 0.20) : lightText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(selected ? accent : Color.white.opacity(0.08)))
                .overlay(Capsule(style: .continuous).stroke(accent.opacity(selected ? 0 : 0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(NewTodoDraft(
            title: trimmed,
            category: category,
            priority: priority,
            dueDate: dueKey,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ))
    }
}

/// Adds a visible hover affordance (slight grow + brighten + pointer cursor) to
/// a bubble's clickable controls. The bubble lives in a non-activating panel, so
/// the stock button highlight is easy to miss; this makes "clickable" obvious.
private struct BubbleClickableHover: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .brightness(isHovering ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

private extension View {
    func bubbleClickableHover() -> some View {
        modifier(BubbleClickableHover())
    }
}

private struct DesktopPetBubbleHeader: View {
    let icon: String
    let title: String
    var trailingBadge: String? = nil
    let onCloseBubble: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(Color(red: 0.42, green: 0.94, blue: 1.0))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.58, green: 0.96, blue: 1.0))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let trailingBadge, !trailingBadge.isEmpty {
                Text(trailingBadge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 1.0))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.08, green: 0.15, blue: 0.40).opacity(0.92))
                    )
            }

            Button(action: onCloseBubble) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.64, green: 0.78, blue: 0.95))
            .help("关闭气泡")
            .bubbleClickableHover()
        }
    }
}

private struct DesktopPetBubbleShell<Content: View>: View {
    let tailOffset: CGFloat
    let tailPosition: DesktopPetBubbleTailPosition
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            if tailPosition == .top {
                bubbleTail
                    .offset(x: tailOffset, y: 1)
            }

            content
                .padding(14)
                .frame(width: 340, alignment: .leading)
                .background(
                    PixelGlassBubbleBackground()
                        .shadow(color: Color(red: 0.07, green: 0.22, blue: 0.62).opacity(0.30), radius: 16, x: 0, y: 8)
                )

            if tailPosition == .bottom {
                bubbleTail
                    .rotationEffect(.degrees(180))
                    .offset(x: tailOffset, y: -1)
            }
        }
    }

    private var bubbleTail: some View {
        SpeechBubbleTail()
            .fill(Color(red: 0.04, green: 0.09, blue: 0.26).opacity(0.98))
            .frame(width: 28, height: 18)
    }
}

private struct PixelGlassBubbleBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.07, blue: 0.21).opacity(0.98),
                        Color(red: 0.06, green: 0.11, blue: 0.34).opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(red: 0.37, green: 0.95, blue: 1.0).opacity(0.78), lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color(red: 0.68, green: 0.99, blue: 1.0).opacity(0.75))
                        .frame(width: 18, height: 3)
                    Rectangle()
                        .fill(Color(red: 0.62, green: 0.46, blue: 1.0).opacity(0.65))
                        .frame(width: 8, height: 3)
                }
                .padding(.top, 8)
                .padding(.leading, 12)
            }
            .overlay(alignment: .bottomTrailing) {
                Rectangle()
                    .fill(Color(red: 0.86, green: 0.46, blue: 1.0).opacity(0.58))
                    .frame(width: 5, height: 5)
                    .padding(10)
            }
    }
}

private struct DesktopPetMascotView: View {
    let isShowingBubble: Bool
    let mood: DesktopPetMood
    let isHovering: Bool
    let edgeAttachment: DesktopPetEdgeAttachment

    @State private var activityPulse = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if isHovering {
                DesktopPetHoverHaloView()
                    .offset(y: -16)
            }

            if !edgeAttachment.isAttached {
                Ellipse()
                    .fill(Color.black.opacity(isHovering ? 0.24 : 0.18))
                    .frame(width: isHovering ? 92 : 82, height: isHovering ? 15 : 13)
                    .blur(radius: isHovering ? 2.5 : 2)
                    .offset(y: 5)
            }

            if mood == .translating && !edgeAttachment.isAttached {
                DesktopPetFootRippleView()
                    .offset(y: 2)
            }

            if let spriteImage {
                Image(nsImage: spriteImage)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
                    .frame(width: 118, height: 140)
                    .scaleEffect(mascotScale, anchor: .bottom)
                    .offset(y: mascotLift)
                    .brightness(spriteBrightness)
            } else {
                fallbackMascot
                    .scaleEffect(mascotScale, anchor: .bottom)
                    .offset(y: mascotLift)
            }

            if mood == .translating {
                DesktopPetLoadingDotsView()
                    .offset(x: 0, y: -88)
            }

            if mood == .learning || mood == .success || isHovering {
                DesktopPetSparklesView(isStrong: mood == .success || isHovering)
            }
        }
        .frame(width: 128, height: 148)
        .shadow(
            color: Color(red: 0.05, green: 0.17, blue: 0.52).opacity(isHovering ? 0.44 : 0.28),
            radius: isHovering ? 8 : 4,
            x: 0,
            y: 3
        )
        .onAppear {
            activityPulse = true
        }
        .animation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true), value: activityPulse)
    }

    private static let spriteImages: [String: NSImage] = {
        let names = [
            "DesktopPetSprite",
            "DesktopPetPeekLeft",
            "DesktopPetPeekRight"
        ]
        return names.reduce(into: [String: NSImage]()) { images, name in
            guard
                let url = Bundle.main.url(forResource: name, withExtension: "png"),
                let image = NSImage(contentsOf: url)
            else {
                return
            }
            images[name] = image
        }
    }()

    private var spriteImage: NSImage? {
        Self.spriteImages[DesktopPetMascotAsset.spriteName(for: edgeAttachment)]
    }

    private var fallbackMascot: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.26, green: 0.49, blue: 0.95))
            .frame(width: 86, height: 96)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.09, blue: 0.28))
                    .frame(width: 58, height: 34)
            }
    }

    private var mascotScale: CGFloat {
        var scale: CGFloat = isShowingBubble ? 1.02 : 1.0
        if isHovering {
            scale += 0.02
        }
        if mood == .success && activityPulse {
            scale += 0.025
        }
        return scale
    }

    private var mascotLift: CGFloat {
        switch mood {
        case .translating:
            return activityPulse ? -3 : 1
        case .learning:
            return activityPulse ? -2 : 0
        case .success:
            return activityPulse ? -5 : 0
        case .idle, .result:
            return 0
        }
    }

    private var pulseDuration: Double {
        switch mood {
        case .translating:
            return 0.58
        case .success:
            return 0.42
        case .learning:
            return 0.86
        case .idle, .result:
            return 1.4
        }
    }

    private var spriteBrightness: Double {
        switch mood {
        case .success:
            return 0.08
        case .translating, .learning:
            return 0.04
        case .idle, .result:
            return isHovering ? 0.04 : 0
        }
    }
}

private struct DesktopPetHoverHaloView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color(red: 0.43, green: 0.95, blue: 1.0).opacity(0.52), lineWidth: 2)
                .frame(width: 122, height: 112)
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color(red: 0.75, green: 0.48, blue: 1.0).opacity(0.34), lineWidth: 1)
                .frame(width: 98, height: 92)
        }
    }
}

private struct DesktopPetFootRippleView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Capsule()
                .stroke(Color(red: 0.36, green: 0.94, blue: 1.0).opacity(0.68), lineWidth: 2)
                .frame(width: 92, height: 18)
                .scaleEffect(pulse ? 1.14 : 0.86)
                .opacity(pulse ? 0.18 : 0.78)
            Capsule()
                .stroke(Color(red: 0.52, green: 0.46, blue: 1.0).opacity(0.45), lineWidth: 1)
                .frame(width: 70, height: 12)
                .scaleEffect(pulse ? 0.92 : 1.06)
                .opacity(pulse ? 0.72 : 0.36)
        }
        .offset(y: -4)
        .onAppear {
            pulse = true
        }
        .animation(.easeOut(duration: 0.72).repeatForever(autoreverses: false), value: pulse)
    }
}

private struct DesktopPetLoadingDotsView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(index == 1
                        ? Color(red: 0.62, green: 0.46, blue: 1.0)
                        : Color(red: 0.42, green: 0.94, blue: 1.0)
                    )
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.14 : 0.72)
                    .opacity(pulse ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.44)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.10),
                        value: pulse
                    )
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.03, green: 0.07, blue: 0.21).opacity(0.82))
        )
        .onAppear {
            pulse = true
        }
    }
}

private struct DesktopPetSparklesView: View {
    let isStrong: Bool

    var body: some View {
        ZStack {
            sparkle(color: Color(red: 0.95, green: 0.48, blue: 1.0), size: isStrong ? 8 : 5)
                .offset(x: -42, y: -74)
            sparkle(color: Color(red: 0.48, green: 0.96, blue: 1.0), size: isStrong ? 7 : 4)
                .offset(x: 42, y: -62)
            sparkle(color: Color(red: 0.55, green: 0.62, blue: 1.0), size: isStrong ? 6 : 4)
                .offset(x: 36, y: -24)
        }
    }

    private func sparkle(color: Color, size: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(color)
                .frame(width: size, height: max(2, size / 3))
            Rectangle()
                .fill(color)
                .frame(width: max(2, size / 3), height: size)
        }
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
