import AppKit
import SwiftUI

/// Free-form notepad (single page), autosaved (debounced) via the store. Edit /
/// preview toggle with Markdown rendering, plus insert-timestamp and copy.
struct TodoMemoView: View {
    @ObservedObject var model: AppModel
    @State private var isPreviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $isPreviewing) {
                    Text("编辑").tag(false)
                    Text("预览").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                Spacer()
                Button { insertTimestamp() } label: { Image(systemName: "clock") }
                    .buttonStyle(.borderless)
                    .help("插入时间戳")
                Button { copyAll() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("复制全部")
            }

            if isPreviewing {
                ScrollView {
                    markdownPreview
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.7)))
            } else {
                TextEditor(text: Binding(
                    get: { model.todoMemo },
                    set: { model.setTodoMemo($0) }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }

            HStack {
                Text("\(model.todoMemo.count) 字")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let updatedAt = model.todoMemoUpdatedAt {
                    Text("更新于 \(updatedAt.relativeDescription)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if model.todoMemo.isEmpty {
            Text("（空）").font(.callout).foregroundStyle(.tertiary)
        } else if let attributed = try? AttributedString(
            markdown: model.todoMemo,
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed).font(.callout).textSelection(.enabled)
        } else {
            Text(model.todoMemo).font(.callout).textSelection(.enabled)
        }
    }

    private func insertTimestamp() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let stamp = "\n## \(formatter.string(from: Date()))\n"
        model.setTodoMemo(model.todoMemo + stamp)
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.todoMemo, forType: .string)
    }
}
