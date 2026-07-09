import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A plain-text editor (bound to a `String`) that additionally renders and
/// accepts *inline images*. Images live in the bound Markdown string as
/// `![](attachments/<uuid>.png)` tokens and on disk via `AttachmentStore`; this
/// editor shows them as true inline `NSTextAttachment`s within the text flow.
///
/// Storage stays a plain `String`, so the memo / todo-note persistence is
/// unchanged — this is purely a richer editing surface over the same data.
struct InlineImageTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Font for typed text. Memo uses monospaced; the todo note uses proportional.
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    /// Max on-screen width for an inline image. Kept modest so a pasted screenshot
    /// shows compact by default rather than filling the whole editor width.
    var maxImageWidth: CGFloat = 280
    /// Called with an image's relative path when the user double-clicks it, so the
    /// host can present it full-size.
    var onActivateImage: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = InlineImageTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true            // required for NSTextAttachment to draw
        textView.importsGraphics = false      // we own image import (see paste)
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.typingAttributes = MarkdownAttachmentCodec.baseAttributes(font: font)
        textView.maxImageWidth = maxImageWidth
        textView.saveImage = { (try? AttachmentStore.save($0)) }
        textView.onActivateImage = { [weak coordinator = context.coordinator] path in
            coordinator?.parent.onActivateImage?(path)
        }

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        // Initial content.
        context.coordinator.isApplyingProgrammaticUpdate = true
        textView.textStorage?.setAttributedString(
            MarkdownAttachmentCodec.attributedString(from: text, font: font)
        )
        context.coordinator.lastSerializedString = text
        context.coordinator.isApplyingProgrammaticUpdate = false
        context.coordinator.resizeAttachments(in: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InlineImageTextView else { return }
        context.coordinator.parent = self

        if text != context.coordinator.lastSerializedString {
            context.coordinator.isApplyingProgrammaticUpdate = true
            let selected = textView.selectedRange()
            let attr = MarkdownAttachmentCodec.attributedString(from: text, font: font)
            textView.textStorage?.setAttributedString(attr)
            textView.typingAttributes = MarkdownAttachmentCodec.baseAttributes(font: font)
            let clamped = NSRange(location: min(selected.location, attr.length), length: 0)
            textView.setSelectedRange(clamped)
            context.coordinator.lastSerializedString = text
            context.coordinator.isApplyingProgrammaticUpdate = false
        }
        // Width may have changed even when text didn't → rescale attachments.
        context.coordinator.resizeAttachments(in: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineImageTextEditor
        /// The exact string we last rendered from or serialized to. `updateNSView`
        /// compares against this to decide whether to rebuild — when a change came
        /// from the user's own typing, `text` already equals this, so no rebuild
        /// (no cursor jump / flicker).
        var lastSerializedString: String = ""
        var isApplyingProgrammaticUpdate = false

        init(_ parent: InlineImageTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate,
                  let textView = notification.object as? InlineImageTextView else { return }
            pushToBinding(from: textView)
        }

        func pushToBinding(from textView: InlineImageTextView) {
            let markdown = MarkdownAttachmentCodec.markdown(from: textView.textStorage)
            lastSerializedString = markdown
            if parent.text != markdown { parent.text = markdown }
        }

        func resizeAttachments(in textView: InlineImageTextView) {
            let width: CGFloat
            if let container = textView.textContainer {
                width = container.size.width - 2 * container.lineFragmentPadding
            } else {
                width = textView.bounds.width
            }
            let cap = min(max(40, width), parent.maxImageWidth)
            MarkdownAttachmentCodec.scaleAttachments(in: textView.textStorage, maxWidth: cap)
        }
    }
}

// MARK: - Attachment carrying its on-disk identity

/// An inline image attachment that remembers which file it represents, so the
/// attributed-string ↔ Markdown round trip is lossless and we never re-save an
/// unchanged image on every keystroke.
final class InlineImageAttachment: NSTextAttachment {
    let relativePath: String

    init(relativePath: String, image: NSImage) {
        self.relativePath = relativePath
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    /// The file is missing on disk — render a placeholder but keep `relativePath`
    /// so serialization re-emits the original token (no data loss).
    init(missingRelativePath relativePath: String) {
        self.relativePath = relativePath
        super.init(data: nil, ofType: nil)
        self.image = Self.placeholderImage(for: relativePath)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private static func placeholderImage(for path: String) -> NSImage {
        let size = NSSize(width: 220, height: 56)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        ("⚠︎ 图片缺失\n" + (path as NSString).lastPathComponent)
            .draw(in: NSRect(x: 10, y: 8, width: size.width - 20, height: size.height - 16), withAttributes: attrs)
        image.unlockFocus()
        return image
    }
}

// MARK: - NSTextView subclass: image paste / drop interception

/// `NSTextView` that intercepts image paste and drag-drop, saving the image via
/// `AttachmentStore` and inserting an inline attachment at the caret. Plain-text
/// paste falls through to the standard behavior.
final class InlineImageTextView: NSTextView {
    /// Resolves a pasted / dropped `NSImage` to a saved relative path (nil on failure).
    var saveImage: ((NSImage) -> String?)?
    /// Max on-screen width for a freshly inserted inline image.
    var maxImageWidth: CGFloat = 280
    /// Called with an inline image's relative path on double-click.
    var onActivateImage: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let path = attachmentRelativePath(at: viewPoint) {
                onActivateImage?(path)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// The relative path of the inline image under `viewPoint`, or nil if the
    /// click didn't land on an attachment.
    private func attachmentRelativePath(at viewPoint: NSPoint) -> String? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerInset.width,
            y: viewPoint.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length,
              let attachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? InlineImageAttachment
        else { return nil }
        // Confirm the click actually fell on the glyph, not past a line end.
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard rect.contains(containerPoint) else { return nil }
        return attachment.relativePath
    }

    override func paste(_ sender: Any?) {
        if insertImageFromPasteboardIfPresent(NSPasteboard.general) { return }
        // Memo / note are plain-text editors: never import RTF runs that have no
        // Markdown representation and would be dropped on serialization.
        pasteAsPlainText(sender)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.png, .tiff, .fileURL] + super.readablePasteboardTypes
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if insertImageFromPasteboardIfPresent(pboard) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    /// Detects an image on `pboard`, saves it, and inserts an inline attachment at
    /// the current selection. Returns false (so the caller can fall back) if no
    /// image was present or saving failed.
    @discardableResult
    func insertImageFromPasteboardIfPresent(_ pboard: NSPasteboard) -> Bool {
        guard let image = Self.image(on: pboard),
              let relativePath = saveImage?(image),
              let stored = AttachmentStore.loadImage(relativePath: relativePath)
        else { return false }
        insertImage(stored, relativePath: relativePath)
        return true
    }

    /// Inserts a scaled inline image attachment at the caret and pushes the change
    /// (undoable). Used by paste, drop, and the optional "insert image" button.
    func insertImage(_ image: NSImage, relativePath: String) {
        let attachment = InlineImageAttachment(relativePath: relativePath, image: image)
        let containerWidth = textContainer.map { $0.size.width - 2 * $0.lineFragmentPadding } ?? bounds.width
        MarkdownAttachmentCodec.scale(attachment, maxWidth: min(max(40, containerWidth), maxImageWidth))

        let attrString = NSMutableAttributedString(attachment: attachment)
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage?.replaceCharacters(in: range, with: attrString)
        setSelectedRange(NSRange(location: range.location + attrString.length, length: 0))
        typingAttributes = MarkdownAttachmentCodec.baseAttributes(font: font ?? .systemFont(ofSize: NSFont.systemFontSize))
        didChangeText()
    }

    private static func image(on pboard: NSPasteboard) -> NSImage? {
        // 1. Direct image (screenshots, copied images from other apps).
        if let images = pboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first { return first }
        // 2. Image file URLs (drag from Finder).
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
           let url = urls.first, let image = NSImage(contentsOf: url) { return image }
        return nil
    }
}

// MARK: - String ↔ NSAttributedString codec

/// Bidirectional codec between the stored Markdown string (with
/// `![](attachments/…)` tokens) and the editor's `NSAttributedString`.
enum MarkdownAttachmentCodec {
    /// Maximum on-screen height for an inline image, so a tall screenshot can't
    /// dominate the editor.
    private static let maxImageHeight: CGFloat = 600

    /// Base typing / text attributes (dynamic label color → dark-mode safe).
    static func baseAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    // MARK: String → NSAttributedString

    static func attributedString(from markdown: String, font: NSFont) -> NSAttributedString {
        let base = baseAttributes(font: font)
        let result = NSMutableAttributedString()
        for segment in InlineMarkdownParser.segments(from: markdown) {
            switch segment {
            case .text(let raw):
                result.append(NSAttributedString(string: raw, attributes: base))
            case .image(let path):
                result.append(attachmentString(forRelativePath: path))
            }
        }
        return result
    }

    private static func attachmentString(forRelativePath path: String) -> NSAttributedString {
        let attachment: InlineImageAttachment
        if let image = AttachmentStore.loadImage(relativePath: path) {
            attachment = InlineImageAttachment(relativePath: path, image: image)
        } else {
            attachment = InlineImageAttachment(missingRelativePath: path)
        }
        return NSAttributedString(attachment: attachment)
    }

    // MARK: NSAttributedString → String

    static func markdown(from storage: NSAttributedString?) -> String {
        guard let storage else { return "" }
        var out = String()
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            if let inline = value as? InlineImageAttachment {
                out += "![](\(inline.relativePath))"
            } else if value is NSTextAttachment {
                // Foreign attachment (shouldn't occur since importsGraphics=false). Skip.
            } else {
                out += (storage.string as NSString).substring(with: range)
            }
        }
        return out
    }

    // MARK: Sizing

    static func scaleAttachments(in storage: NSTextStorage?, maxWidth: CGFloat) {
        guard let storage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? InlineImageAttachment { scale(attachment, maxWidth: maxWidth) }
        }
    }

    static func scale(_ attachment: NSTextAttachment, maxWidth: CGFloat) {
        guard let image = attachment.image else { return }
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return }
        var width = min(natural.width, maxWidth)
        var height = natural.height * (width / natural.width)
        if height > maxImageHeight {
            height = maxImageHeight
            width = natural.width * (height / natural.height)
        }
        attachment.bounds = CGRect(x: 0, y: 0, width: width, height: height)
    }
}
