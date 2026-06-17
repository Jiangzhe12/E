import SwiftUI

/// A single dense todo row inside the merged date-group container. One line:
/// status toggle · priority dot · title · subtask progress · due pill ·
/// category chip · hover actions · expand chevron. The expandable detail holds
/// tags, note, bug fields, subtasks, and the changelog.
struct TodoRowView: View {
    @ObservedObject var model: AppModel
    let todo: TodoItem
    let today: String
    let onEdit: (TodoItem) -> Void

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var newSubtask = ""

    private var isDone: Bool { todo.status == .done }
    private var hasDetail: Bool {
        (todo.note?.isEmpty == false) || (todo.subtasks?.isEmpty == false)
            || (todo.tags?.isEmpty == false) || todo.isBug || (todo.changelog?.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mainRow
            if isExpanded {
                detailSection
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.white.opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("切换为 \(todo.status.next.chineseLabel)") { model.toggleTodoStatus(id: todo.id) }
            Button("编辑…") { onEdit(todo) }
            if !model.todoSortByPriority {
                Button("上移") { model.moveTodo(id: todo.id, in: todo.date, up: true) }
                Button("下移") { model.moveTodo(id: todo.id, in: todo.date, up: false) }
            }
            if todo.isBug && todo.convertedToOptimizationId == nil {
                Button("转为优化项") { model.convertBugToOptimization(bugId: todo.id) }
            }
            if isDone {
                Button("归档") { model.archiveTodo(id: todo.id) }
            }
            Divider()
            Button("删除", role: .destructive) { model.deleteTodo(id: todo.id) }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 9) {
            Button {
                model.toggleTodoStatus(id: todo.id)
            } label: {
                Image(systemName: TodoPalette.statusSymbol(todo.status))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TodoPalette.status(todo.status))
            }
            .buttonStyle(.borderless)
            .help("切换状态（\(todo.status.next.chineseLabel)）")

            if todo.priority == .high {
                Circle().fill(Color(red: 0.937, green: 0.267, blue: 0.267)).frame(width: 7, height: 7)
            } else if todo.priority == .low {
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
            }

            Text(todo.title)
                .font(.body.weight(.medium))
                .strikethrough(isDone, color: .secondary)
                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let subtasks = todo.subtasks, !subtasks.isEmpty {
                Text("\(subtasks.filter(\.done).count)/\(subtasks.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !isDone, let due = todoDueInfo(dueDate: todo.dueDate, today: today) {
                let colors = TodoPalette.due(due.kind)
                Text(due.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.fg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(colors.bg))
            }

            Text(todo.category.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TodoPalette.category(todo.category))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(TodoPalette.category(todo.category).opacity(0.14)))

            if isHovering {
                Button { onEdit(todo) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("编辑")
                if isDone {
                    Button { model.archiveTodo(id: todo.id) } label: { Image(systemName: "archivebox") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("归档")
                }
                Button { model.deleteTodo(id: todo.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(Color(red: 0.80, green: 0.30, blue: 0.30)).help("删除")
            }

            if hasDetail {
                Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help(isExpanded ? "收起" : "展开")
            }
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tags = todo.tags, !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.40, green: 0.45, blue: 0.60))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color(red: 0.90, green: 0.92, blue: 0.97)))
                    }
                }
            }

            if let note = todo.note, !note.isEmpty {
                noteView(note)
            }

            if todo.isBug, (todo.bugCause?.isEmpty == false) || (todo.fixPlan?.isEmpty == false) {
                VStack(alignment: .leading, spacing: 3) {
                    if let cause = todo.bugCause, !cause.isEmpty {
                        Text("原因：\(cause)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let plan = todo.fixPlan, !plan.isEmpty {
                        Text("方案：\(plan)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            subtasksView

            if let changelog = todo.changelog, !changelog.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("变更记录").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    ForEach(Array(changelog.suffix(20).reversed().enumerated()), id: \.offset) { _, entry in
                        Text(changelogText(entry))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.leading, 25)
    }

    @ViewBuilder
    private func noteView(_ note: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: note,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        } else {
            Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private var subtasksView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let subtasks = todo.subtasks {
                ForEach(subtasks) { subtask in
                    HStack(spacing: 6) {
                        Button { model.toggleSubtask(todoId: todo.id, subtaskId: subtask.id) } label: {
                            Image(systemName: subtask.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(subtask.done ? TodoPalette.status(.done) : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        Text(subtask.title)
                            .font(.caption)
                            .strikethrough(subtask.done, color: .secondary)
                            .foregroundStyle(subtask.done ? .secondary : .primary)
                        Spacer(minLength: 0)
                        Button { model.removeSubtask(todoId: todo.id, subtaskId: subtask.id) } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                TextField("添加子任务", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit {
                        model.addSubtask(todoId: todo.id, title: newSubtask)
                        newSubtask = ""
                    }
            }
        }
    }

    private func changelogText(_ entry: ChangeLogEntry) -> String {
        let field = TodoFieldLabel.chinese(entry.field)
        let from = entry.oldValue ?? "—"
        let to = entry.newValue ?? "—"
        return "\(entry.timestamp.relativeDescription) · \(field)：\(from) → \(to)"
    }
}

enum TodoFieldLabel {
    static func chinese(_ field: String) -> String {
        switch field {
        case "title": return "标题"
        case "category": return "分类"
        case "priority": return "优先级"
        case "status": return "状态"
        case "dueDate": return "截止"
        case "note": return "备注"
        default: return field
        }
    }
}
