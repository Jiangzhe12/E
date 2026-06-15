import AppKit
import ApplicationServices
import Foundation

enum SelectedTextServiceError: LocalizedError {
    case accessibilityDenied
    case noFocusedElement
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "请先授予辅助功能权限，才能跨应用读取选中文本。"
        case .noFocusedElement:
            return "当前无法获取焦点元素，请先在目标应用选中文本。"
        case .noSelectedText:
            return "没有读取到选中文本。"
        }
    }
}

final class SelectedTextService {
    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func fetchSelectedText() throws -> SelectedTextSnapshot {
        guard AXIsProcessTrusted() else {
            throw SelectedTextServiceError.accessibilityDenied
        }

        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElementRef: CFTypeRef?
        let focusedElementError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusedElementError == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            throw SelectedTextServiceError.noFocusedElement
        }

        let focusedElement = focusedElementRef as! AXUIElement
        var selectedTextRef: CFTypeRef?
        let selectedTextError = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        guard selectedTextError == .success,
              let selectedText = selectedTextRef as? String,
              !selectedText.trimmed.isEmpty else {
            throw SelectedTextServiceError.noSelectedText
        }

        let sourceAppName = focusedApplicationName(systemWideElement: systemWideElement)
        let context = surroundingSentence(for: focusedElement, selectedText: selectedText)

        return SelectedTextSnapshot(
            text: selectedText,
            sourceAppName: sourceAppName,
            context: context
        )
    }

    /// Best-effort capture of the sentence the selection sits inside, read from
    /// the focused element's full text + selected range. Returns `nil` when the
    /// element doesn't expose that data, or when the sentence isn't meaningfully
    /// longer than the selection (e.g. the user already selected a whole line).
    private func surroundingSentence(for element: AXUIElement, selectedText: String) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success,
            let rangeRef,
            CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange),
              cfRange.location >= 0,
              cfRange.length >= 0
        else { return nil }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success,
            let fullText = valueRef as? String,
            !fullText.isEmpty
        else { return nil }

        let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
        guard let sentence = Self.enclosingSentence(in: fullText, selectionRange: nsRange) else {
            return nil
        }

        // Only worth keeping if it adds context beyond the selection itself.
        guard sentence.count > selectedText.trimmed.count else { return nil }
        // Guard against pathologically long blobs (selection inside a giant
        // textarea with no sentence punctuation).
        guard sentence.count <= TranslationLimits.maxCharacters else { return nil }
        return sentence
    }

    /// Extracts the sentence in `fullText` that contains the start of `nsRange`.
    static func enclosingSentence(in fullText: String, selectionRange nsRange: NSRange) -> String? {
        guard let selection = Range(nsRange, in: fullText) else { return nil }

        var found: String?
        fullText.enumerateSubstrings(
            in: fullText.startIndex ..< fullText.endIndex,
            options: .bySentences
        ) { substring, subRange, _, stop in
            guard let substring else { return }
            if subRange.contains(selection.lowerBound) || subRange.lowerBound == selection.lowerBound {
                found = substring.trimmingCharacters(in: .whitespacesAndNewlines)
                stop = true
            }
        }
        return (found?.isEmpty == false) ? found : nil
    }

    /// Returns the screen position of the text cursor (caret) in the focused
    /// element of the frontmost app, or `nil` when Accessibility is unavailable
    /// or the focused element doesn't expose caret bounds.
    func focusedElementCursorPosition() -> NSPoint? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        let focusedElement = focusedRef as! AXUIElement

        // Try to get the caret rect via the selected text range.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef else {
            // Fall back to the focused element's own position.
            return elementPosition(focusedElement)
        }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef else {
            return elementPosition(focusedElement)
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else {
            return elementPosition(focusedElement)
        }

        // CG coordinates (top-left origin) → AppKit (bottom-left origin).
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(
            x: rect.origin.x + rect.width / 2,
            y: screenHeight - rect.origin.y - rect.height
        )
    }

    /// Position of an AXUIElement (top-left corner), converted to AppKit coords.
    private func elementPosition(_ element: AXUIElement) -> NSPoint? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &posRef
        ) == .success, let posRef else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point) else {
            return nil
        }

        var sizeRef: CFTypeRef?
        var size = CGSize.zero
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }

        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        // Return a point near the top-center of the element.
        return NSPoint(
            x: point.x + size.width / 2,
            y: screenHeight - point.y - min(size.height, 40)
        )
    }

    private func focusedApplicationName(systemWideElement: AXUIElement) -> String? {
        var focusedAppRef: CFTypeRef?
        let appError = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )

        guard appError == .success,
              let appElement = focusedAppRef,
              CFGetTypeID(appElement) == AXUIElementGetTypeID() else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid((appElement as! AXUIElement), &pid)
        guard pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
