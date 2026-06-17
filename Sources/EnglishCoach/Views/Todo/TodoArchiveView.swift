import SwiftUI

/// Sheet listing archived todos grouped by date, with restore / delete actions.
struct TodoArchiveView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    private var groups: [(date: String, todos: [TodoItem])] {
        let grouped = Dictionary(grouping: model.archivedTodos, by: { $0.date })
        return grouped.keys.sorted(by: >).map { ($0, (grouped[$0] ?? []).sorted { $0.order < $1.order }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("归档", systemImage: "archivebox")
                    .font(.headline)
                    .foregroundStyle(TodoPalette.title)
                Spacer()
                Text("\(model.archivedTodos.count) 项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button("完成", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            if groups.isEmpty {
                VStack(spacing: 6) {
                    Text("📦").font(.largeTitle)
                    Text("还没有归档的待办").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(String(group.date.suffix(5)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(group.todos) { todo in
                                    HStack(spacing: 8) {
                                        Image(systemName: todo.category.systemImage)
                                            .font(.caption)
                                            .foregroundStyle(TodoPalette.category(todo.category))
                                        Text(todo.title)
                                            .font(.callout)
                                            .strikethrough(todo.status == .done, color: .secondary)
                                            .lineLimit(1)
                                        Spacer(minLength: 6)
                                        Button("还原") { model.unarchiveTodo(id: todo.id) }
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                        Button { model.deleteTodo(id: todo.id) } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(Color(red: 0.80, green: 0.30, blue: 0.30))
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.6))
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }
}
