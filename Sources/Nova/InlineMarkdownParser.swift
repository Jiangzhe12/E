import Foundation

/// One renderable piece of an inline-image Markdown string.
///
/// Inline images are stored inside the otherwise-plain Markdown strings
/// (`model.todoMemo`, `TodoItem.note`) as the reference `![](attachments/<uuid>.png)`.
/// The actual PNG lives on disk under the app's `attachments/` directory; the
/// string only ever holds the relative path. See `AttachmentStore`.
enum InlineSegment: Equatable {
    /// Raw Markdown sub-string (may span multiple lines). Render via `AttributedString(markdown:)`.
    case text(String)
    /// An inline image, identified by its `attachments/<uuid>.png` relative path.
    case image(relativePath: String)
}

/// Splits an inline-image Markdown string into ordered text / image segments.
///
/// Shared by the editable editor (`InlineImageTextEditor`) and the read-only
/// renderer (`InlineMarkdownView`) so both agree on exactly which tokens are
/// treated as inline images — keeping the regex in one place avoids drift.
///
/// The pattern is intentionally anchored to the `attachments/` prefix so that
/// ordinary remote-image Markdown (`![](https://…)`) is left untouched as text.
enum InlineMarkdownParser {
    /// Matches `![alt](attachments/<anything-but-)-or-whitespace>)`. The alt text
    /// is ignored; capture group 1 is the relative path.
    static let imageTokenPattern = #"!\[[^\]]*\]\((attachments/[^)\s]+)\)"#

    private static let regex = try? NSRegularExpression(pattern: imageTokenPattern)

    /// Splits `markdown` into ordered text / image segments. Reading order is
    /// preserved; adjacent image tokens produce back-to-back `.image` segments
    /// with no spurious empty text run between them.
    static func segments(from markdown: String) -> [InlineSegment] {
        guard let regex, !markdown.isEmpty else {
            return markdown.isEmpty ? [] : [.text(markdown)]
        }
        let ns = markdown as NSString
        var result: [InlineSegment] = []
        var cursor = 0
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                let text = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                if !text.isEmpty { result.append(.text(text)) }
            }
            let path = ns.substring(with: match.range(at: 1))
            result.append(.image(relativePath: path))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            if !tail.isEmpty { result.append(.text(tail)) }
        }
        return result
    }
}
