import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

/// Detects a "double ⌘C" gesture across apps.
///
/// - Preferred path: a `CGEventTap` that listens for real ⌘C keyDown events. We
///   only trigger when the user actually pressed ⌘C twice in quick succession
///   *and* the clipboard content actually changed. This avoids false positives
///   when another app rewrites the clipboard or when ⌘C is part of an unrelated
///   keyboard combo.
/// - Fallback: if the event tap cannot be installed (accessibility permission
///   not granted, macOS sandbox restrictions, etc.) we fall back to the old
///   polling-based heuristic — that one still works without permission.
@MainActor
final class GlobalHotkeyManager: NSObject {
    var onHotKeyPressed: (() -> Void)?
    var onQuickTranslatePressed: (() -> Void)?

    private var doubleCopyInterval: TimeInterval = 0.8

    // Carbon hotkey path (⌘E — no Accessibility permission needed)
    private var carbonHotkeyRef: EventHotKeyRef?
    private var carbonEventHandlerRef: EventHandlerRef?

    // Event-tap path
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastCommandCAt: Date = .distantPast
    private var lastEventTapChangeCount: Int
    private var eventTapObserverRef: UnsafeMutableRawPointer?

    // Polling fallback path
    private var pollingTimer: Timer?
    private var pollingLastChangeCount: Int
    private var pollingLastCopiedText: String = ""
    private var pollingLastCopiedAt: Date = .distantPast

    override init() {
        let initialCount = NSPasteboard.general.changeCount
        self.lastEventTapChangeCount = initialCount
        self.pollingLastChangeCount = initialCount
        super.init()
    }

    // No `deinit` cleanup: this manager is owned by `AppModel` for the entire
    // app lifetime, so resource teardown happens implicitly when the process
    // exits. Adding a nonisolated `deinit` would need to touch main-actor
    // state, which the Swift 6 strict-concurrency checker refuses.

    func setDoubleCopyInterval(_ interval: TimeInterval) {
        doubleCopyInterval = min(max(interval, 0.3), 1.5)
    }

    /// Install the best available hotkey source. Calling this more than once is
    /// a no-op.
    func registerDefaultShortcut() throws {
        // ⌘E via Carbon API — works without Accessibility permission.
        installCarbonHotkey()

        if eventTap != nil || pollingTimer != nil {
            return
        }

        if installEventTap() {
            return
        }

        installPollingFallback()
    }

    /// Tears down whatever detection mode is currently in place and picks again
    /// (e.g. to upgrade from polling fallback to CGEventTap once the user has
    /// granted Accessibility permission in System Settings).
    func reRegisterIfNeeded() {
        let wasUsingEventTap = eventTap != nil
        let canUseEventTap = AXIsProcessTrusted()

        if wasUsingEventTap && canUseEventTap {
            return
        }
        if !wasUsingEventTap && !canUseEventTap {
            return
        }

        tearDownEventTap()
        pollingTimer?.invalidate()
        pollingTimer = nil

        if canUseEventTap && installEventTap() {
            return
        }
        installPollingFallback()
    }

    // MARK: - Carbon hotkey (⌘E)

    private func installCarbonHotkey() {
        guard carbonHotkeyRef == nil else { return }

        let observerRef = Unmanaged.passUnretained(self).toOpaque()

        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, inUserData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let inUserData else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    let mgr = Unmanaged<GlobalHotkeyManager>
                        .fromOpaque(inUserData).takeUnretainedValue()
                    mgr.onQuickTranslatePressed?()
                }
                return noErr
            },
            1,
            &eventType,
            observerRef,
            &carbonEventHandlerRef
        )
        guard status == noErr else { return }

        let hotkeyID = EventHotKeyID(
            signature: OSType(0x454E4743), // "ENGC"
            id: UInt32(1)
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(cmdKey),
            hotkeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &carbonHotkeyRef
        )
    }

    // MARK: - Event tap

    private func installEventTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let observerRef = Unmanaged.passUnretained(self).toOpaque()
        self.eventTapObserverRef = observerRef

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            // The event tap source is attached to the main run loop in
            // `installEventTap`, so CoreGraphics dispatches this callback on
            // the main thread. `assumeIsolated` tells the compiler we really
            // are on `@MainActor` without paying for a queue hop.
            MainActor.assumeIsolated {
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                manager.handleEventTapEvent(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: observerRef
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    private func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        eventTapObserverRef = nil
    }

    private func handleEventTapEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        case .keyDown:
            break
        default:
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // `c` = 8 on every Mac keyboard layout. (⌘E is handled by Carbon API.)
        guard keyCode == 8 else { return }

        let flags = event.flags
        let isCommand = flags.contains(.maskCommand)
        let hasForbiddenModifier = flags.contains(.maskShift)
            || flags.contains(.maskAlternate)
            || flags.contains(.maskControl)
        guard isCommand, !hasForbiddenModifier else { return }

        let now = Date()
        let interval = now.timeIntervalSince(lastCommandCAt)
        lastCommandCAt = now

        guard interval > 0, interval <= doubleCopyInterval else { return }

        // Give the system a moment to actually copy the selection before we
        // read the pasteboard.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            self?.evaluateDoubleCommandC()
        }
    }

    private func evaluateDoubleCommandC() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastEventTapChangeCount else { return }
        lastEventTapChangeCount = pasteboard.changeCount

        guard let copied = pasteboard.string(forType: .string)?.trimmed,
              !copied.isEmpty else {
            return
        }

        onHotKeyPressed?()
    }

    // MARK: - Polling fallback

    private func installPollingFallback() {
        let timer = Timer.scheduledTimer(
            timeInterval: 0.2,
            target: self,
            selector: #selector(handlePollingTick),
            userInfo: nil,
            repeats: true
        )
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc
    private func handlePollingTick() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pollingLastChangeCount else {
            return
        }
        pollingLastChangeCount = pasteboard.changeCount

        guard let copiedText = pasteboard.string(forType: .string)?.trimmed,
              !copiedText.isEmpty else {
            return
        }

        let now = Date()
        let isDoubleCopy = copiedText == pollingLastCopiedText
            && now.timeIntervalSince(pollingLastCopiedAt) <= doubleCopyInterval

        pollingLastCopiedText = copiedText
        pollingLastCopiedAt = now

        if isDoubleCopy {
            onHotKeyPressed?()
        }
    }
}
