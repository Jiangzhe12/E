import SwiftUI

/// Manage reusable todo templates: list existing ones (create a task / delete)
/// and add new ones.
struct TodoTemplateView: View {
    @ObservedObject var model: AppModel

    @State private var isAdding = false
    @State private var name = ""
    @State private var category: TodoCategory = .feature
    @State private var priority: TodoPriority = .medium
    @State private var subtasksText = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("模板").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { isAdding.toggle() }
                } label: {
                    Label(isAdding ? "收起" : "新建模板", systemImage: isAdding ? "chevron.up" : "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isAdding { addForm }

            if model.templates.isEmpty {
                Text("还没有模板。常用的任务可以存成模板，一键创建。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.templates) { template in
                    templateRow(template)
                }
            }
        }
    }

    private func templateRow(_ template: TodoTemplate) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(template.category.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TodoPalette.category(template.category))
                    Text("优先级 \(template.priority.title)").font(.caption2).foregroundStyle(.secondary)
                    if let subtasks = template.subtasks, !subtasks.isEmpty {
                        Text("\(subtasks.count) 子任务").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let tags = template.tags, !tags.isEmpty {
                        Text(tags.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 6)
            Button("新建任务") { model.createTodoFromTemplate(id: template.id) }
                .buttonStyle(.borderless)
                .font(.caption)
            Button { model.deleteTemplate(id: template.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.danger)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.glass(0.8)))
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("模板名称", text: $name).textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Picker("", selection: $category) {
                    ForEach(TodoCategory.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Picker("", selection: $priority) {
                    ForEach(TodoPriority.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            TextField("子任务（逗号分隔）", text: $subtasksText).textFieldStyle(.roundedBorder)
            TextField("备注", text: $note).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("保存模板") {
                    let subtasks = subtasksText
                        .split(whereSeparator: { $0 == "," || $0 == "，" })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    model.addTemplate(name: name, category: category, priority: priority, tags: [], subtasks: subtasks, note: note)
                    name = ""; subtasksText = ""; note = ""
                    withAnimation { isAdding = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.glass(0.6)))
    }
}
