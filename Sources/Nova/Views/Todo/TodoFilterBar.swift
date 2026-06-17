import SwiftUI

/// Collapsible filter chips (category / status / tags) for the todo list.
/// Search and priority-sort live in the list view's control row.
struct TodoFilterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("分类").font(.caption2).foregroundStyle(.tertiary).frame(width: 30, alignment: .leading)
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
                Text("状态").font(.caption2).foregroundStyle(.tertiary).frame(width: 30, alignment: .leading)
                TodoPill(title: "全部", isActive: model.todoFilterStatus == nil) {
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

            if !model.customTags.isEmpty {
                HStack(spacing: 6) {
                    Text("标签").font(.caption2).foregroundStyle(.tertiary).frame(width: 30, alignment: .leading)
                    ForEach(model.customTags, id: \.self) { tag in
                        TodoPill(
                            title: "#\(tag)",
                            color: AppColor.subtitle,
                            isActive: model.todoFilterTag == tag
                        ) {
                            model.todoFilterTag = model.todoFilterTag == tag ? "" : tag
                        }
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
                .foregroundStyle(isActive ? AppColor.onAccent : color)
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
