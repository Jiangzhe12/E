import AppKit
import SwiftUI

/// The desktop-pet floating panel. Borderless panels can't become key by
/// default, which blocks text input. We let it become key only while an
/// in-bubble form (e.g. 新建待办) is showing, so typing works then but the pet
/// stays non-activating the rest of the time.
final class DesktopPetPanel: NSPanel {
    var keyInputEnabled = false
    override var canBecomeKey: Bool { keyInputEnabled }
    override var canBecomeMain: Bool { false }
}

/// A lightweight floating panel that shows ⌘C⌘C translation results near the
/// mouse cursor without stealing keyboard focus from the user's current app.
@MainActor
final class TranslationPopoverController: NSObject, NSWindowDelegate {
    private var panel: DesktopPetPanel?
    private var autoDismissTimer: Timer?
    private var autoDismissAction: (() -> Void)?
    private var globalClickMonitor: Any?
    private let desktopPetState = DesktopPetPresentationState()
    private let desktopPetLayoutMetrics = DesktopPetLayoutMetrics()
    private var desktopPetAnchorPoint: NSPoint?
    private var desktopPetEdgeSnapTask: Task<Void, Never>?
    private var isApplyingDesktopPetFrame = false
    private let speechService = SpeechService()

    private var desktopPetIdlePanelSize: NSSize {
        desktopPetLayoutMetrics.idlePanelSize
    }

    private var desktopPetBubblePanelSize: NSSize {
        desktopPetLayoutMetrics.bubblePanelSize
    }

    var onOpenMainWindow: (() -> Void)?
    var onRequestQuickTranslate: (() -> Void)?
    var onRequestClipboardTranslation: (() -> Void)?
    var onRequestDailyWord: (() -> Void)?
    var onRequestLastTranslation: (() -> Void)?
    var onDailyWordComplete: ((DesktopWordCard) -> Void)?
    var onDailyWordPractice: ((DesktopWordCard) -> Void)?
    var onStartNextDailyWordGroup: (() -> Void)?
    var onAddToLearning: ((TranslationResult) -> Void)?
    var onRequestQuickAddTodo: (() -> Void)?
    var onRequestShowTodos: (() -> Void)?
    var onCompleteTodo: ((String) -> Void)?
    var onRequestOpenTodoList: (() -> Void)?
    var onSubmitNewTodo: ((NewTodoDraft) -> Void)?

    private var quickTranslatePanel: NSPanel?
    private let quickPanelWidth: CGFloat = 420

    // MARK: - Quick Translate panel (⌘E)

    func presentQuickTranslate(model: AppModel, near point: NSPoint) {
        if let existing = quickTranslatePanel, existing.isVisible {
            existing.orderFrontRegardless()
            existing.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(
            rootView: QuickTranslatePopoverView(
                model: model,
                speechService: speechService,
                onClose: { [weak self] in
                    self?.dismissQuickTranslate()
                },
                onOpenMainWindow: { [weak self] in
                    self?.onOpenMainWindow?()
                    self?.dismissQuickTranslate()
                }
            )
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: quickPanelWidth, height: 200),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: 360, height: 180)
        panel.contentView = hostingView

        positionPanel(panel, near: point)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        quickTranslatePanel = panel
    }

    func dismissQuickTranslate() {
        quickTranslatePanel?.orderOut(nil)
    }

    // MARK: - New-todo form bubble (pet right-click)

    /// Show the new-todo form inside the pet's speech bubble. Makes the panel
    /// key so the bubble's text fields accept typing.
    func presentTodoFormBubble() {
        cancelAutoDismissTimer()
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: nil) {
            desktopPetState.showTodoForm()
        }
    }

    // MARK: - Result popover (⌘C⌘C)

    func showDesktopPet(near point: NSPoint? = nil) {
        let panel = ensureDesktopPetPanel()
        if !panel.isVisible {
            positionDesktopPetPanel(panel, near: point, size: desktopPetIdlePanelSize)
        } else if !desktopPetState.hasBubble {
            resizeDesktopPetPanel(panel, to: desktopPetIdlePanelSize)
        }
        panel.orderFrontRegardless()
    }

    func hideDesktopPet() {
        cancelAutoDismissTimer()
        removeGlobalClickMonitor()
        desktopPetState.clearBubble()
        if let panel {
            resizeDesktopPetPanel(panel, to: desktopPetIdlePanelSize)
        }
        desktopPetAnchorPoint = nil
        panel?.orderOut(nil)
    }

    func presentTranslating(text: String, near point: NSPoint) {
        cancelAutoDismissTimer()
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: point) {
            desktopPetState.showTranslating(text)
        }
    }

    func present(result: TranslationResult, sourceAppName: String?, near point: NSPoint) {
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: point) {
            desktopPetState.show(result: result, sourceAppName: sourceAppName)
        }

        startAutoDismissTimer()
        installGlobalClickMonitorIfNeeded()
    }

    func presentDailyWordInvite(card: DesktopWordCard) {
        cancelAutoDismissTimer()
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: nil) {
            desktopPetState.showDailyWordInvite(card)
        }
    }

    func presentActionMenu() {
        cancelAutoDismissTimer()
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: nil) {
            desktopPetState.showActionMenu()
        }
    }

    func presentDailyWordCompletion(message: String) {
        cancelAutoDismissTimer()
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: nil) {
            desktopPetState.showDailyWordCompletion(message: message)
        }
    }

    func presentTodoBubble(rows: [DesktopPetTodoRow], openCount: Int) {
        cancelAutoDismissTimer()
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: nil) {
            desktopPetState.showTodos(rows: rows, openCount: openCount)
        }
    }

    func presentFeedback(
        title: String,
        message: String,
        autoDismissAfter seconds: TimeInterval = DesktopPetBubbleTiming.defaultAutoDismissSeconds,
        onAutoDismiss: (() -> Void)? = nil
    ) {
        let panel = ensureDesktopPetPanel()
        presentDesktopPetBubble(panel, near: nil) {
            desktopPetState.showFeedback(title: title, message: message)
        }
        startAutoDismissTimer(after: seconds, onDismiss: onAutoDismiss)
    }

    func dismiss() {
        cancelAutoDismissTimer()
        removeGlobalClickMonitor()
        panel?.keyInputEnabled = false
        if let panel, panel.isVisible {
            syncDesktopPetAnchor(from: panel)
            desktopPetState.clearBubble()
            resizeDesktopPetPanel(panel, to: desktopPetIdlePanelSize)
        } else {
            desktopPetState.clearBubble()
        }
    }

    private func ensureDesktopPetPanel() -> NSPanel {
        if let panel {
            return panel
        }

        let hostingView = NSHostingView(
            rootView: DesktopPetTranslationView(
                state: desktopPetState,
                onCopy: { [weak self] result in
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(result.translatedText, forType: .string)
                    self?.presentFeedback(title: "已复制", message: result.translatedText)
                },
                onOpenMainWindow: { [weak self] in
                    self?.onOpenMainWindow?()
                    self?.dismiss()
                },
                onQuickTranslate: { [weak self] in
                    self?.dismiss()
                    self?.onRequestQuickTranslate?()
                },
                onTranslateClipboard: { [weak self] in
                    self?.onRequestClipboardTranslation?()
                },
                onShowDailyWord: { [weak self] in
                    self?.onRequestDailyWord?()
                },
                onShowLastTranslation: { [weak self] in
                    self?.onRequestLastTranslation?()
                },
                onQuitApp: {
                    NSApp.terminate(nil)
                },
                onSpeak: { [weak self] result in
                    let lang = result.direction == .chineseToEnglish ? "zh-CN" : "en-US"
                    self?.speechService.speak(result.originalText, languageCode: lang)
                },
                onAddToLearning: { [weak self] result in
                    self?.onAddToLearning?(result)
                },
                onCloseBubble: { [weak self] in
                    self?.dismiss()
                },
                onPetTap: { [weak self] in
                    self?.presentActionMenu()
                },
                onPetSecondaryTap: { [weak self] in
                    self?.onRequestQuickAddTodo?()
                },
                onShowDailyWordMeaning: { [weak self] card in
                    self?.desktopPetState.showDailyWordMeaning(card)
                },
                onDailyWordComplete: { [weak self] card in
                    self?.onDailyWordComplete?(card)
                },
                onDailyWordPractice: { [weak self] card in
                    self?.onDailyWordPractice?(card)
                },
                onStartNextDailyWordGroup: { [weak self] in
                    self?.onStartNextDailyWordGroup?()
                },
                onSpeakDailyWord: { [weak self] card in
                    self?.speechService.speak(card.word)
                },
                onQuickAddTodo: { [weak self] in
                    self?.onRequestQuickAddTodo?()
                },
                onShowTodos: { [weak self] in
                    self?.onRequestShowTodos?()
                },
                onCompleteTodo: { [weak self] id in
                    self?.onCompleteTodo?(id)
                },
                onOpenTodoList: { [weak self] in
                    self?.onRequestOpenTodoList?()
                    self?.dismiss()
                },
                onSubmitNewTodo: { [weak self] draft in
                    self?.onSubmitNewTodo?(draft)
                }
            )
        )
        hostingView.setFrameSize(desktopPetIdlePanelSize)

        let panel = DesktopPetPanel(
            contentRect: NSRect(origin: .zero, size: desktopPetIdlePanelSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Without this a non-activating panel never forwards mouse-moved events,
        // so SwiftUI `.onHover` / button hover highlights inside the bubble never
        // fire. Enable it so the bubble's clickable controls show hover feedback.
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleDesktopPetWindowDidMove()
        }
    }

    private func positionPanel(_ panel: NSPanel, near mouseLocation: NSPoint) {
        let panelSize = panel.frame.size
        let margin: CGFloat = 12

        // Place the panel so its top edge is just below the cursor.
        var origin = NSPoint(
            x: mouseLocation.x + 12,
            y: mouseLocation.y - panelSize.height - 8
        )

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // Keep within horizontal bounds.
            if origin.x + panelSize.width + margin > visible.maxX {
                origin.x = mouseLocation.x - panelSize.width - 12
            }
            if origin.x < visible.minX + margin {
                origin.x = visible.minX + margin
            }
            // If it goes below the screen, flip to above the cursor.
            if origin.y < visible.minY + margin {
                origin.y = mouseLocation.y + 8
            }
            if origin.y + panelSize.height + margin > visible.maxY {
                origin.y = visible.maxY - panelSize.height - margin
            }
        }

        panel.setFrameOrigin(origin)
    }

    private func positionDesktopPetPanel(
        _ panel: NSPanel,
        near point: NSPoint?,
        size: NSSize? = nil
    ) {
        let panelSize = size ?? panel.frame.size
        let margin: CGFloat = 22
        let targetPoint = point ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(targetPoint) })
            ?? NSScreen.main

        guard let visible = screen?.visibleFrame else { return }

        let anchor = desktopPetAnchorPoint ?? defaultDesktopPetAnchor(in: visible, margin: margin)
        desktopPetAnchorPoint = anchor

        applyDesktopPetFrame(
            panel,
            size: panelSize,
            anchor: anchor,
            visibleFrame: visible
        )
    }

    private func resizeDesktopPetPanel(_ panel: NSPanel, to size: NSSize) {
        let current = panel.frame
        syncDesktopPetAnchor(from: panel)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(current) })
            ?? NSScreen.main

        guard
            let currentAnchor = desktopPetAnchorPoint,
            let visible = screen?.visibleFrame
        else { return }

        applyDesktopPetFrame(
            panel,
            size: size,
            anchor: currentAnchor,
            visibleFrame: visible
        )
    }

    private func applyDesktopPetFrame(
        _ panel: NSPanel,
        size: NSSize,
        anchor: NSPoint,
        visibleFrame visible: NSRect
    ) {
        if isDesktopPetBubbleSize(size) {
            let layout = DesktopPetLayout.bubbleLayout(
                for: anchor,
                visibleFrame: visible,
                metrics: desktopPetLayoutMetrics,
                edgeAttachment: desktopPetState.edgeAttachment
            )
            desktopPetState.setBubblePlacement(layout.placement)
            setDesktopPetFrame(panel, layout.frame, display: true)
            return
        }

        let frame = DesktopPetLayout.idleFrame(
            for: anchor,
            visibleFrame: visible,
            metrics: desktopPetLayoutMetrics
        )
        desktopPetState.setEdgeAttachment(
            DesktopPetLayout.edgeAttachment(for: frame, visibleFrame: visible)
        )
        setDesktopPetFrame(panel, frame, display: true)
    }

    private func presentDesktopPetBubble(
        _ panel: NSPanel,
        near point: NSPoint?,
        updateState: () -> Void
    ) {
        let targetPoint = point ?? NSEvent.mouseLocation
        let screen = panel.isVisible
            ? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main
            : NSScreen.screens.first(where: { $0.frame.contains(targetPoint) }) ?? NSScreen.main

        guard let visible = screen?.visibleFrame else {
            withoutDesktopPetTransitionAnimation(updateState)
            panel.orderFrontRegardless()
            return
        }

        if panel.isVisible {
            syncDesktopPetAnchor(from: panel)
        }

        let anchor = desktopPetAnchorPoint ?? defaultDesktopPetAnchor(in: visible, margin: 22)
        desktopPetAnchorPoint = anchor
        let layout = DesktopPetLayout.bubbleLayout(
            for: anchor,
            visibleFrame: visible,
            metrics: desktopPetLayoutMetrics,
            edgeAttachment: desktopPetState.edgeAttachment
        )

        panel.disableScreenUpdatesUntilFlush()
        setDesktopPetFrame(panel, layout.frame, display: false)
        withoutDesktopPetTransitionAnimation {
            desktopPetState.setBubblePlacement(layout.placement)
            updateState()
        }
        panel.displayIfNeeded()
        panel.orderFrontRegardless()

        // Only the in-bubble form needs keyboard input; enable key + activate
        // for it, and keep the pet non-activating for every other bubble.
        if let petPanel = panel as? DesktopPetPanel {
            if case .todoForm = desktopPetState.bubble {
                petPanel.keyInputEnabled = true
                NSApp.activate(ignoringOtherApps: true)
                petPanel.makeKeyAndOrderFront(nil)
            } else {
                petPanel.keyInputEnabled = false
            }
        }
    }

    private func syncDesktopPetAnchor(from panel: NSPanel) {
        desktopPetAnchorPoint = DesktopPetLayout.mascotAnchor(
            in: panel.frame,
            placement: desktopPetState.bubblePlacement,
            metrics: desktopPetLayoutMetrics
        )
    }

    private func handleDesktopPetWindowDidMove() {
        guard
            let movedPanel = panel,
            !isApplyingDesktopPetFrame
        else { return }

        syncDesktopPetAnchor(from: movedPanel)

        guard !desktopPetState.hasBubble else { return }
        scheduleDesktopPetEdgeSnap(for: movedPanel)
    }

    private func scheduleDesktopPetEdgeSnap(for panel: NSPanel) {
        desktopPetEdgeSnapTask?.cancel()
        desktopPetEdgeSnapTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard
                !Task.isCancelled,
                let self,
                let panel
            else { return }
            self.applyDesktopPetEdgeSnap(to: panel)
        }
    }

    private func applyDesktopPetEdgeSnap(to panel: NSPanel) {
        guard !desktopPetState.hasBubble else { return }
        guard NSEvent.pressedMouseButtons == 0 else {
            scheduleDesktopPetEdgeSnap(for: panel)
            return
        }

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        syncDesktopPetAnchor(from: panel)
        guard let anchor = desktopPetAnchorPoint else { return }
        applyDesktopPetFrame(
            panel,
            size: desktopPetIdlePanelSize,
            anchor: anchor,
            visibleFrame: visible
        )
    }

    private func setDesktopPetFrame(_ panel: NSPanel, _ frame: NSRect, display: Bool) {
        isApplyingDesktopPetFrame = true
        panel.setFrame(frame, display: display)
        isApplyingDesktopPetFrame = false
    }

    private func defaultDesktopPetAnchor(in visible: NSRect, margin: CGFloat) -> NSPoint {
        NSPoint(
            x: visible.maxX - desktopPetIdlePanelSize.width / 2 - margin,
            y: visible.minY + desktopPetLayoutMetrics.mascotAnchorYOffset + margin
        )
    }

    private func isDesktopPetBubbleSize(_ size: NSSize) -> Bool {
        size.width > desktopPetIdlePanelSize.width + 1
            || size.height > desktopPetIdlePanelSize.height + 1
    }

    private func withoutDesktopPetTransitionAnimation(_ body: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    private func cancelAutoDismissTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        autoDismissAction = nil
    }

    private func startAutoDismissTimer(
        after seconds: TimeInterval = DesktopPetBubbleTiming.defaultAutoDismissSeconds,
        onDismiss: (() -> Void)? = nil
    ) {
        cancelAutoDismissTimer()
        autoDismissAction = onDismiss
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAutoDismissTimerFired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoDismissTimer = timer
    }

    private func handleAutoDismissTimerFired() {
        let action = autoDismissAction
        autoDismissAction = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        dismiss()
        action?()
    }

    private func installGlobalClickMonitorIfNeeded() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
    }

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}

// MARK: - Quick Translate floating input panel (⌘E)

struct QuickTranslatePopoverView: View {
    @ObservedObject var model: AppModel
    let speechService: SpeechService
    let onClose: () -> Void
    let onOpenMainWindow: () -> Void

    @State private var inputText: String = ""
    @State private var translationResult: TranslationResult?
    @State private var isTranslating: Bool = false
    @State private var directionChoice: TranslationDirectionChoice = .auto
    @FocusState private var isInputFocused: Bool

    private var effectiveDirection: TranslationDirection {
        directionChoice.concreteDirection ?? TranslationService.detectDirection(inputText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(AppColor.subtitle)
                Text("快速翻译")
                    .font(.headline)
                    .foregroundStyle(AppColor.title)
                Spacer()
                Picker("", selection: $directionChoice) {
                    ForEach(TranslationDirectionChoice.allCases) { choice in
                        Text(choice.displayLabel).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 180)
                if isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Input
            TextEditor(text: $inputText)
                .font(.callout)
                .frame(minHeight: 50, maxHeight: 100)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .focused($isInputFocused)
                .onAppear { isInputFocused = true }

            HStack {
                Text("⌘⏎ 翻译  ·  Esc 关闭")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("翻译") {
                    performTranslate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(inputText.trimmed.isEmpty || isTranslating)
            }

            // Result area
            if let result = translationResult {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    TranslationResultBody(
                        original: result.originalText,
                        translated: result.translatedText,
                        phonetic: result.phonetic,
                        explanations: Array(result.explanations.prefix(3)),
                        originalLineLimit: 2,
                        style: .panel
                    ) {
                        Spacer(minLength: 4)
                        Text(result.direction.displayLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                    }

                    HStack(spacing: 10) {
                        Button("复制译文") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(result.translatedText, forType: .string)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button {
                            let lang = result.direction == .chineseToEnglish ? "zh-CN" : "en-US"
                            speechService.speak(result.originalText, languageCode: lang)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("朗读原文")
                        if model.canAddLookupToLearning(result) {
                            Button {
                                model.addLookupToLearning(result)
                            } label: {
                                Image(systemName: "text.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("加入生词本")
                        }
                        Button("展开到主窗口", action: onOpenMainWindow)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer()
                        Text(result.provider)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 360, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .onExitCommand(perform: onClose)
    }

    private func performTranslate() {
        let text = inputText
        let direction = directionChoice.concreteDirection
        isTranslating = true
        Task { @MainActor in
            let result = await model.translateForQuickPanel(text, direction: direction)
            isTranslating = false
            if let result {
                translationResult = result
            }
        }
    }
}
