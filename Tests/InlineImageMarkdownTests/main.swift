import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

// Plain text, no image → single text segment.
expect(InlineMarkdownParser.segments(from: "hello") == [.text("hello")], "plain text")

// Empty string → no segments.
expect(InlineMarkdownParser.segments(from: "").isEmpty, "empty -> none")

// Image only.
expect(
    InlineMarkdownParser.segments(from: "![](attachments/a.png)") == [.image(relativePath: "attachments/a.png")],
    "image only"
)

// Image token with alt text.
expect(
    InlineMarkdownParser.segments(from: "![shot](attachments/b.png)") == [.image(relativePath: "attachments/b.png")],
    "image with alt text"
)

// Mid-paragraph token splits around surrounding text.
expect(
    InlineMarkdownParser.segments(from: "see ![alt](attachments/x.png) here")
        == [.text("see "), .image(relativePath: "attachments/x.png"), .text(" here")],
    "image mid-paragraph"
)

// Multiple images preserve order, no spurious empty text between adjacent ones.
expect(
    InlineMarkdownParser.segments(from: "![](attachments/1.png)![](attachments/2.png)")
        == [.image(relativePath: "attachments/1.png"), .image(relativePath: "attachments/2.png")],
    "adjacent images, no empty text run"
)

// Newline between two images is kept as a (tiny) text segment, order preserved.
let multi = InlineMarkdownParser.segments(from: "![](attachments/1.png)\n![](attachments/2.png)")
expect(multi.first == .image(relativePath: "attachments/1.png"), "first image first")
expect(multi.last == .image(relativePath: "attachments/2.png"), "last image last")
expect(multi.filter { if case .image = $0 { return true } else { return false } }.count == 2, "two images")

// Remote / non-attachment markdown image is left as plain text (not split).
expect(
    InlineMarkdownParser.segments(from: "![](https://x.com/y.png)") == [.text("![](https://x.com/y.png)")],
    "remote image left as text"
)

// Leading text then image.
expect(
    InlineMarkdownParser.segments(from: "note: ![](attachments/c.png)")
        == [.text("note: "), .image(relativePath: "attachments/c.png")],
    "leading text then image"
)

print("InlineImageMarkdownTests passed")
