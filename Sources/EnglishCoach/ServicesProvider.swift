import AppKit
import Foundation

/// Bridges the macOS Services menu to `AppModel`.
///
/// Registered via `NSApp.servicesProvider = ...` on launch. The system calls
/// `translateText:userData:error:` (selector name fixed by `NSMessage` in
/// Info.plist) whenever the user picks "用 EnglishCoach 翻译" from the Services
/// menu in any app — no Accessibility permission required.
@MainActor
final class ServicesProvider: NSObject {
    weak var appModel: AppModel?

    /// Selector exposed to the ObjC runtime. The explicit `@objc(...)` name
    /// must match `NSMessage` in the Info.plist `NSServices` entry, otherwise
    /// macOS silently drops the menu item.
    @objc(translateText:userData:error:)
    func translateText(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard let text = pasteboard.string(forType: .string)?.trimmed,
              !text.isEmpty else {
            errorPointer?.pointee = "没有读取到选中文本" as NSString
            return
        }

        // Hop onto the main actor in a detached task so the ObjC caller
        // returns immediately and macOS doesn't spin waiting on our work.
        Task { @MainActor [weak appModel] in
            appModel?.translateFromServicesMenu(text: text)
        }
    }
}
