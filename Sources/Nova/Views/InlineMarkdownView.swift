import AppKit
import SwiftUI

/// Read-only renderer for Markdown that may contain inline-image tokens
/// `![](attachments/<uuid>.png)`. Used by the memo Preview tab and the todo-row
/// note detail.
///
/// SwiftUI's `Text(AttributedString(markdown:))` does not load local-file
/// images, so we split the string into ordered text / image segments (via
/// `InlineMarkdownParser`) and render each: text via `AttributedString`, image
/// via `Image(nsImage:)` loaded from `AttachmentStore`. Images render as their
/// own block between text runs (the editable `InlineImageTextEditor` is where
/// images sit truly within the text flow).
struct InlineMarkdownView: View {
    let markdown: String
    var interpretedSyntax: AttributedString.MarkdownParsingOptions.InterpretedSyntax = .full
    var font: Font = .callout
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var maxImageWidth: CGFloat = 320
    var spacing: CGFloat = 6

    @State private var lightbox: LightboxImage?

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(InlineMarkdownParser.segments(from: markdown).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let raw):
                    if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        textView(raw)
                    }
                case .image(let path):
                    imageView(path)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $lightbox) { item in
            ImageLightboxView(relativePath: item.relativePath) { lightbox = nil }
        }
    }

    @ViewBuilder
    private func textView(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: interpretedSyntax)
        ) {
            Text(attributed).font(font).foregroundStyle(foregroundStyle).textSelection(.enabled)
        } else {
            Text(raw).font(font).foregroundStyle(foregroundStyle).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func imageView(_ relativePath: String) -> some View {
        if let nsImage = AttachmentStore.loadImage(relativePath: relativePath) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: min(maxImageWidth, nsImage.size.width), alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onTapGesture(count: 2) { lightbox = LightboxImage(relativePath: relativePath) }
                .help("双击查看大图")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "photo.badge.exclamationmark")
                Text("图片缺失").font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: maxImageWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.glass(0.4)))
        }
    }
}

/// Identifies an inline image to present full-size in a lightbox sheet.
struct LightboxImage: Identifiable {
    let id = UUID()
    let relativePath: String
}

/// Full-size image viewer presented as a resizable sheet. Drag the corner to
/// enlarge, or open in the system viewer (Preview) for full zoom / pan.
struct ImageLightboxView: View {
    let relativePath: String
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Spacer()
                Button { openInViewer() } label: {
                    Label("用预览打开", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                Button("完成", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            Group {
                if let image = AttachmentStore.loadImage(relativePath: relativePath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                        Text("图片缺失").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 820, minHeight: 320, idealHeight: 620)
    }

    private func openInViewer() {
        if let url = AttachmentStore.url(forRelativePath: relativePath) {
            NSWorkspace.shared.open(url)
        }
    }
}
