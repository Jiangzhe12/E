import AppKit
import SwiftUI

@MainActor
final class DesktopPetPresentationState: ObservableObject {
    @Published var result: TranslationResult?
    @Published var sourceAppName: String?

    var content: DesktopPetBubbleContent? {
        guard let result else { return nil }
        return DesktopPetBubbleContent(result: result, sourceAppName: sourceAppName)
    }

    func show(result: TranslationResult, sourceAppName: String?) {
        self.result = result
        self.sourceAppName = sourceAppName
    }

    func clearBubble() {
        result = nil
        sourceAppName = nil
    }
}

struct DesktopPetTranslationView: View {
    @ObservedObject var state: DesktopPetPresentationState
    let onCopy: (TranslationResult) -> Void
    let onOpenMainWindow: () -> Void
    let onSpeak: (TranslationResult) -> Void
    let onCloseBubble: () -> Void

    @State private var isFloating = false

    private var panelSize: CGSize {
        state.result == nil
            ? CGSize(width: 148, height: 156)
            : CGSize(width: 424, height: 316)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if let result = state.result, let content = state.content {
                    DesktopPetBubbleView(
                        content: content,
                        result: result,
                        onCopy: onCopy,
                        onOpenMainWindow: onOpenMainWindow,
                        onSpeak: onSpeak,
                        onCloseBubble: onCloseBubble
                    )
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
                }

                DesktopPetMascotView(isShowingBubble: state.result != nil)
                    .offset(y: isFloating ? -4 : 2)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: isFloating
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .bottom)
        .background(Color.clear)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state.result?.id)
        .onAppear {
            isFloating = true
        }
        .onExitCommand(perform: onCloseBubble)
    }
}

private struct DesktopPetBubbleView: View {
    let content: DesktopPetBubbleContent
    let result: TranslationResult
    let onCopy: (TranslationResult) -> Void
    let onOpenMainWindow: () -> Void
    let onSpeak: (TranslationResult) -> Void
    let onCloseBubble: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .foregroundStyle(Color(red: 0.16, green: 0.53, blue: 0.66))

                    Text(content.metadata)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.28, blue: 0.36))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(action: onCloseBubble) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("关闭气泡")
                }

                Text(content.originalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(content.translatedText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.08, green: 0.17, blue: 0.28))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if let phonetic = content.phonetic {
                    Text(phonetic)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(red: 0.28, green: 0.39, blue: 0.50))
                        .lineLimit(1)
                }

                if !content.explanationBullets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(content.explanationBullets.enumerated()), id: \.offset) { _, explanation in
                            Text("· \(explanation)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        onCopy(result)
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onSpeak(result)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("朗读原文")

                    Button {
                        onOpenMainWindow()
                    } label: {
                        Label("展开", systemImage: "rectangle.arrowtriangle.2.outward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text(content.provider)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: 340, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                    .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )

            SpeechBubbleTail()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                .frame(width: 28, height: 18)
                .offset(x: -66, y: -1)
        }
    }
}

private struct DesktopPetMascotView: View {
    let isShowingBubble: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: 82, height: 13)
                .blur(radius: 2)
                .offset(y: 5)

            if let spriteImage = Self.spriteImage {
                Image(nsImage: spriteImage)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
                    .frame(width: 118, height: 140)
                    .scaleEffect(isShowingBubble ? 1.02 : 1.0, anchor: .bottom)
            } else {
                fallbackMascot
            }
        }
        .frame(width: 128, height: 148)
        .shadow(color: Color(red: 0.05, green: 0.17, blue: 0.52).opacity(0.28), radius: 4, x: 0, y: 3)
    }

    private static let spriteImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "DesktopPetSprite", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private var fallbackMascot: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.26, green: 0.49, blue: 0.95))
            .frame(width: 86, height: 96)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.09, blue: 0.28))
                    .frame(width: 58, height: 34)
            }
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
