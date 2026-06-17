import SwiftUI

/// The 待办 tab's content: header + quick-add, filter bar, date-grouped list,
/// and an undo affordance. Calendar / templates / memo / weekly-report subviews
/// arrive in later phases.
struct TodoRootView: View {
    @ObservedObject var model: AppModel

    @State private var quickAddTitle: String = ""
    @State private var isShowingAddForm: Bool = false
    @State private var isShowingArchive: Bool = false
    @State private var editingTodo: TodoItem?

    private var today: String { todoDayKey(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            quickAddRow
            if let deleted = model.deletedTodo {
                undoBanner(deleted)
            }
            TodoFilterBar(model: model)
            listContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.74))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                )
        )
        .sheet(isPresented: $isShowingAddForm) {
            TodoFormView(model: model, editing: nil) { isShowingAddForm = false }
        }
        .sheet(item: $editingTodo) { todo in
            TodoFormView(model: model, editing: todo) { editingTodo = nil }
        }
        .sheet(isPresented: $isShowingArchive) {
            TodoArchiveView(model: model) { isShowingArchive = false }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("待办清单", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(TodoPalette.title)
            Spacer()
            Text("\(model.openTodoCount) 项待完成")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Menu {
                Button("归档已完成") { model.archiveDoneTodos() }
                Button("查看归档（\(model.archivedTodos.count)）") { isShowingArchive = true }
            } label: {
                Image(systemName: "archivebox")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("归档")
            Button {
                isShowingAddForm = true
            } label: {
                Label("详细新建", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var quickAddRow: some View {
        HStack(spacing: 8) {
            TextField("快速添加一项待办…", text: $quickAddTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitQuickAdd)
            Button("添加", action: submitQuickAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(quickAddTitle.trimmed.isEmpty)
        }
    }

    private func submitQuickAdd() {
        let title = quickAddTitle.trimmed
        guard !title.isEmpty else { return }
        model.addTodo(title: title)
        quickAddTitle = ""
    }

    private func undoBanner(_ todo: TodoItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("已删除「\(todo.title)」")
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("撤销") { model.undoDeleteTodo() }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.90))
        )
    }

    @ViewBuilder
    private var listContent: some View {
        let groups = model.visibleTodoGroups
        if groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.todos.isEmpty ? "还没有待办，添加第一项吧 ✅" : "没有符合筛选条件的待办")
                    .font(.callout.weight(.semibold))
                Text("也可以在桌宠菜单里「快速记待办」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.6))
            )
        } else {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(todoGroupHeader(for: group.date, today: today))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.27, green: 0.40, blue: 0.55))
                        Text("\(group.todos.filter { $0.status != .done }.count) 项")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ForEach(group.todos) { todo in
                        TodoRowView(model: model, todo: todo, today: today) { editingTodo = $0 }
                    }
                }
            }
        }
    }
}
