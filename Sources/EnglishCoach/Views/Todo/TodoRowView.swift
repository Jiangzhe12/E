import SwiftUI

/// A single todo row in the main-window list. Mirrors the web app's row: status
/// toggle, category badge, priority dot, subtask progress, due-date pill, note
/// preview, and hover-revealed edit/delete actions.
struct TodoRowView: View {
    @ObservedObject var model: AppModel
    let todo: TodoItem
    let today: String
    let onEdit: (TodoItem) -> Void

    @State private var isHovering = false

    private var isDone: Bool { todo.status == .done }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                model.toggleTodoStatus(id: todo.id)
            } label: {
                Image(systemName: TodoPalette.statusSymbol(todo.status))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TodoPalette.status(todo.status))
            }
            .buttonStyle(.borderless)
            .help("切换状态（\(todo.status.next.chineseLabel)）")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if todo.priority == .high {
                        Circle().fill(Color(red: 0.937, green: 0.267, blue: 0.267)).frame(width: 7, height: 7)
                    } else if todo.priority == .low {
                        Circle().fill(Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    }

                    Text(todo.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDone, color: .secondary)
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtasks = todo.subtasks, !subtasks.isEmpty {
                        Text("\(subtasks.filter(\.done).count)/\(subtasks.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Label(todo.category.title, systemImage: todo.category.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TodoPalette.category(todo.category))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TodoPalette.category(todo.category).opacity(0.14))
                        )

                    if !isDone, let due = todoDueInfo(dueDate: todo.dueDate, today: today) {
                        let colors = TodoPalette.due(due.kind)
                        Text(due.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.fg)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(colors.bg))
                    }

                    if let tags = todo.tags, !tags.isEmpty {
                        ForEach(tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(Color(red: 0.40, green: 0.45, blue: 0.60))
                        }
                    }
                }

                if let note = todo.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if isHovering {
                    Button { onEdit(todo) } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("编辑")

                    Button { model.deleteTodo(id: todo.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color(red: 0.80, green: 0.30, blue: 0.30))
                    .help("删除")
                }
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isDone ? 0.55 : 0.80))
        )
        .opacity(isDone ? 0.78 : 1.0)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("切换为 \(todo.status.next.chineseLabel)") { model.toggleTodoStatus(id: todo.id) }
            Button("编辑…") { onEdit(todo) }
            Divider()
            Button("删除", role: .destructive) { model.deleteTodo(id: todo.id) }
        }
    }
}
