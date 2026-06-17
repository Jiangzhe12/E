import SwiftUI

/// Search + category + status filters for the todo list. Expanded with
/// priority-sort and tag pills in a later phase.
struct TodoFilterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索待办（标题 / 备注）", text: $model.todoSearchQuery)
                    .textFieldStyle(.plain)
                if !model.todoSearchQuery.isEmpty {
                    Button { model.todoSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )

            HStack(spacing: 6) {
                TodoPill(title: "全部", isActive: model.todoFilterCategory == nil) {
                    model.todoFilterCategory = nil
                }
                ForEach(TodoCategory.allCases) { category in
                    TodoPill(
                        title: category.title,
                        color: TodoPalette.category(category),
                        isActive: model.todoFilterCategory == category
                    ) {
                        model.todoFilterCategory = model.todoFilterCategory == category ? nil : category
                    }
                }
            }

            HStack(spacing: 6) {
                TodoPill(title: "全部状态", isActive: model.todoFilterStatus == nil) {
                    model.todoFilterStatus = nil
                }
                ForEach(TodoStatus.allCases) { status in
                    TodoPill(
                        title: status.chineseLabel,
                        color: TodoPalette.status(status),
                        isActive: model.todoFilterStatus == status
                    ) {
                        model.todoFilterStatus = model.todoFilterStatus == status ? nil : status
                    }
                }
            }
        }
    }
}

struct TodoPill: View {
    let title: String
    var color: Color = TodoPalette.title
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? color : color.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}
