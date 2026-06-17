import SwiftUI

/// Add / edit sheet for a todo. Shows bug-specific fields when the category is
/// Bug. Calls `addTodo` for new items and `updateTodo` when editing.
struct TodoFormView: View {
    @ObservedObject var model: AppModel
    /// `nil` when adding a new todo.
    let editing: TodoItem?
    let onClose: () -> Void

    @State private var title: String
    @State private var category: TodoCategory
    @State private var priority: TodoPriority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var note: String
    @State private var bugCause: String
    @State private var fixPlan: String

    init(model: AppModel, editing: TodoItem?, onClose: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.onClose = onClose
        _title = State(initialValue: editing?.title ?? "")
        _category = State(initialValue: editing?.category ?? .feature)
        _priority = State(initialValue: editing?.priority ?? .medium)
        _hasDueDate = State(initialValue: editing?.dueDate != nil)
        _dueDate = State(initialValue: Self.parseDay(editing?.dueDate) ?? Date())
        _note = State(initialValue: editing?.note ?? "")
        _bugCause = State(initialValue: editing?.bugCause ?? "")
        _fixPlan = State(initialValue: editing?.fixPlan ?? "")
    }

    private var canSave: Bool { !title.trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "新建待办" : "编辑待办")
                .font(.headline)
                .foregroundStyle(TodoPalette.title)

            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分类").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $category) {
                        ForEach(TodoCategory.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("优先级").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $priority) {
                        ForEach(TodoPriority.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Toggle(isOn: $hasDueDate) {
                Text("设置截止日期")
            }
            if hasDueDate {
                DatePicker("截止日期", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }

            if category == .bug {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bug 详情").font(.caption).foregroundStyle(.secondary)
                    TextField("问题原因", text: $bugCause)
                        .textFieldStyle(.roundedBorder)
                    TextField("修复方案", text: $fixPlan)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("备注（支持 Markdown）").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.body)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("取消", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "添加" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let dueKey = hasDueDate ? todoDayKey(for: dueDate) : nil
        let trimmedCause = bugCause.trimmed
        let trimmedFix = fixPlan.trimmed
        let trimmedNote = note.trimmed

        if let editing {
            model.updateTodo(id: editing.id) { item in
                item.title = title.trimmed
                item.category = category
                item.priority = priority
                item.dueDate = dueKey
                item.note = trimmedNote.isEmpty ? nil : trimmedNote
                if category == .bug {
                    item.bugCause = trimmedCause.isEmpty ? nil : trimmedCause
                    item.fixPlan = trimmedFix.isEmpty ? nil : trimmedFix
                }
            }
        } else {
            model.addTodo(
                title: title,
                category: category,
                priority: priority,
                dueDate: dueKey,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                bugCause: category == .bug && !trimmedCause.isEmpty ? trimmedCause : nil,
                fixPlan: category == .bug && !trimmedFix.isEmpty ? trimmedFix : nil
            )
        }
        onClose()
    }

    private static func parseDay(_ key: String?) -> Date? {
        guard let key else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
