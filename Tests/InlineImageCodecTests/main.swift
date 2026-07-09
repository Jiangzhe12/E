import AppKit
import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

let font = NSFont.systemFont(ofSize: 13)

// Round-trip: markdown → attributed → markdown must be identity for inline-image
// tokens, even when the underlying files are missing (the attachment still
// carries its relativePath, so no data is lost). This is the core guarantee.
func roundTrip(_ markdown: String) -> String {
    let attr = MarkdownAttachmentCodec.attributedString(from: markdown, font: font)
    return MarkdownAttachmentCodec.markdown(from: attr)
}

expect(roundTrip("") == "", "empty round-trips")
expect(roundTrip("hello world") == "hello world", "plain text round-trips")
expect(roundTrip("![](attachments/a.png)") == "![](attachments/a.png)", "single image round-trips")
expect(
    roundTrip("before ![](attachments/x.png) after") == "before ![](attachments/x.png) after",
    "image mid-text round-trips"
)
expect(
    roundTrip("![](attachments/1.png)![](attachments/2.png)") == "![](attachments/1.png)![](attachments/2.png)",
    "adjacent images round-trip in order"
)
expect(
    roundTrip("line1\n![](attachments/x.png)\nline2") == "line1\n![](attachments/x.png)\nline2",
    "image with newlines round-trips"
)

// Alt text is normalized to empty on re-emit (we always write `![](path)`).
expect(
    roundTrip("![screenshot](attachments/x.png)") == "![](attachments/x.png)",
    "alt text normalized on re-emit"
)

// The attributed string contains an InlineImageAttachment carrying the path.
let attr = MarkdownAttachmentCodec.attributedString(from: "![](attachments/keep.png)", font: font)
var foundPath: String?
attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
    if let inline = value as? InlineImageAttachment { foundPath = inline.relativePath }
}
expect(foundPath == "attachments/keep.png", "attachment carries its relativePath")

print("InlineImageCodecTests passed")
