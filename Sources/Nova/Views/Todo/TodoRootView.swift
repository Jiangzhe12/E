import SwiftUI

enum TodoSubview: String, CaseIterable, Identifiable {
    case list
    case calendar
    case report
    case templates
    case memo

    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: return "列表"
        case .calendar: return "日历"
        case .report: return "周报"
        case .templates: return "模板"
        case .memo: return "便签"
        }
    }
}

/// The 待办 tab's content: a segmented sub-navigation over the list, calendar,
/// and stats views. Templates / memo / weekly-report subviews arrive in later
/// phases.
struct TodoRootView: View {
    @ObservedObject var model: AppModel

    @State private var subview: TodoSubview = .list
    @State private var quickAddTitle: String = ""
    @State private var isShowingAddForm: Bool = false
    @State private var isShowingArchive: Bool = false
    @State private var isShowingFilters: Bool = false
    @State private var editingTodo: TodoItem?

    private var today: String { todoDayKey(for: Date()) }

    /// Count of active (non-default) filters, shown as a badge on 筛选.
    private var activeFilterCount: Int {
        (model.todoFilterCategory != nil ? 1 : 0)
            + (model.todoFilterStatus != nil ? 1 : 0)
            + (model.todoFilterTag.isEmpty ? 0 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Picker("", selection: $subview) {
                ForEach(TodoSubview.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch subview {
            case .list:
                listSubview
            case .calendar:
                TodoCalendarView(model: model) { editingTodo = $0 }
            case .report:
                WeeklyReportView(model: model)
            case .templates:
                TodoTemplateView(model: model)
            case .memo:
                TodoMemoView(model: model)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
            .help("归档").accessibilityLabel("归档")
            Button {
                isShowingAddForm = true
            } label: {
                Label("详细新建", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var listSubview: some View {
        quickAddRow
        if let deleted = model.deletedTodo {
            undoBanner(deleted)
        }
        controlRow
        if isShowingFilters {
            TodoFilterBar(model: model)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.glass(0.55))
                )
        }
        summaryStrip
        listContent
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

    /// Search + collapsible-filter toggle + priority sort, on one compact line.
    private var controlRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索标题 / 备注", text: $model.todoSearchQuery)
                    .textFieldStyle(.plain)
                if !model.todoSearchQuery.isEmpty {
                    Button { model.todoSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.glass(0.7)))

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isShowingFilters.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("筛选")
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColor.onAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(AppColor.title))
                    }
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isShowingFilters || activeFilterCount > 0 ? TodoPalette.title : .secondary)

            Button {
                model.todoSortByPriority.toggle()
            } label: {
                Image(systemName: model.todoSortByPriority ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(model.todoSortByPriority ? TodoPalette.title : .secondary)
            .help("按优先级排序").accessibilityLabel("按优先级排序")
        }
    }

    /// Slim one-line summary replacing the four large stat blocks.
    private var summaryStrip: some View {
        let stats = model.todoStats
        return HStack(spacing: 10) {
            Text("今日 ")
                .font(.caption).foregroundStyle(.secondary)
            + Text("\(stats.todayDone)/\(stats.todayTotal)")
                .font(.caption.weight(.semibold)).foregroundStyle(TodoPalette.title)
            + Text(" 完成").font(.caption).foregroundStyle(.secondary)

            ProgressView(value: Double(stats.todayDone), total: Double(max(stats.todayTotal, 1)))
                .frame(maxWidth: 150)
                .tint(TodoPalette.status(.done))

            Spacer()

            Text("进行中 \(stats.inProgress) · 待办 \(stats.pending) · 逾期 \(stats.overdue)")
                .font(.caption2)
                .foregroundStyle(stats.overdue > 0 ? TodoPalette.orange : .secondary)
        }
        .padding(.horizontal, 2)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
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
                    .fill(Color.glass(0.6))
            )
        } else {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(todoGroupHeader(for: group.date, today: today))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.subtitle)
                        Text("\(group.todos.count) 项")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    // Merge a date group's rows into one container with hairline
                    // dividers so it reads as a single list, not floating cards.
                    VStack(spacing: 0) {
                        ForEach(Array(group.todos.enumerated()), id: \.element.id) { index, todo in
                            if index > 0 {
                                Divider().opacity(0.5).padding(.leading, 38)
                            }
                            TodoRowView(model: model, todo: todo, today: today) { editingTodo = $0 }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.glass(0.80))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}
