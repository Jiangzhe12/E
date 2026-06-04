import AppKit
import SwiftUI

/// A lightweight floating panel that shows ⌘C⌘C translation results near the
/// mouse cursor without stealing keyboard focus from the user's current app.
@MainActor
final class TranslationPopoverController {
    private var panel: NSPanel?
    private var autoDismissTimer: Timer?
    private var globalClickMonitor: Any?
    private let desktopPetState = DesktopPetPresentationState()
    private let desktopPetIdlePanelSize = NSSize(width: 148, height: 156)
    private let desktopPetBubblePanelSize = NSSize(width: 424, height: 316)
    private let speechService = SpeechService()

    var onOpenMainWindow: (() -> Void)?

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

    // MARK: - Result popover (⌘C⌘C)

    func showDesktopPet(near point: NSPoint? = nil) {
        let panel = ensureDesktopPetPanel()
        if !panel.isVisible {
            positionDesktopPetPanel(panel, near: point, size: desktopPetIdlePanelSize)
        } else if desktopPetState.result == nil {
            resizeDesktopPetPanel(panel, to: desktopPetIdlePanelSize)
        }
        panel.orderFrontRegardless()
    }

    func hideDesktopPet() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        removeGlobalClickMonitor()
        desktopPetState.clearBubble()
        if let panel {
            resizeDesktopPetPanel(panel, to: desktopPetIdlePanelSize)
        }
        panel?.orderOut(nil)
    }

    func present(result: TranslationResult, sourceAppName: String?, near point: NSPoint) {
        let panel = ensureDesktopPetPanel()
        if !panel.isVisible {
            positionDesktopPetPanel(panel, near: point, size: desktopPetBubblePanelSize)
        } else {
            resizeDesktopPetPanel(panel, to: desktopPetBubblePanelSize)
        }
        desktopPetState.show(result: result, sourceAppName: sourceAppName)
        panel.orderFrontRegardless()

        startAutoDismissTimer()
        installGlobalClickMonitorIfNeeded()
    }

    func dismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        removeGlobalClickMonitor()
        desktopPetState.clearBubble()
        if let panel, panel.isVisible {
            resizeDesktopPetPanel(panel, to: desktopPetIdlePanelSize)
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
                    self?.dismiss()
                },
                onOpenMainWindow: { [weak self] in
                    self?.onOpenMainWindow?()
                    self?.dismiss()
                },
                onSpeak: { [weak self] result in
                    let lang = result.direction == .chineseToEnglish ? "zh-CN" : "en-US"
                    self?.speechService.speak(result.originalText, languageCode: lang)
                },
                onCloseBubble: { [weak self] in
                    self?.dismiss()
                }
            )
        )
        hostingView.setFrameSize(desktopPetIdlePanelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: desktopPetIdlePanelSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        self.panel = panel
        return panel
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

        let origin = NSPoint(
            x: visible.maxX - panelSize.width - margin,
            y: visible.minY + margin
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
    }

    private func resizeDesktopPetPanel(_ panel: NSPanel, to size: NSSize) {
        let current = panel.frame
        let anchoredOrigin = NSPoint(
            x: current.maxX - size.width,
            y: current.minY
        )
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(current) })
            ?? NSScreen.main

        guard let visible = screen?.visibleFrame else {
            panel.setFrame(NSRect(origin: anchoredOrigin, size: size), display: true)
            return
        }

        let margin: CGFloat = 8
        var origin = anchoredOrigin
        if origin.x < visible.minX + margin {
            origin.x = visible.minX + margin
        }
        if origin.x + size.width > visible.maxX - margin {
            origin.x = visible.maxX - size.width - margin
        }
        if origin.y < visible.minY + margin {
            origin.y = visible.minY + margin
        }
        if origin.y + size.height > visible.maxY - margin {
            origin.y = visible.maxY - size.height - margin
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func startAutoDismissTimer() {
        autoDismissTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoDismissTimer = timer
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
                    .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
                Text("快速翻译")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(result.originalText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text(result.direction.displayLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(result.translatedText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.10, green: 0.21, blue: 0.36))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if let phonetic = result.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if !result.explanations.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(result.explanations.prefix(3).enumerated()), id: \.offset) { _, explanation in
                                Text("· \(explanation)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
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
