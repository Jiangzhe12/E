import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

func makeTodo(
    id: String,
    date: String,
    order: Int,
    category: TodoCategory = .feature,
    status: TodoStatus = .pending,
    priority: TodoPriority = .medium,
    archived: Bool = false,
    title: String? = nil,
    note: String? = nil,
    tags: [String]? = nil
) -> TodoItem {
    TodoItem(
        id: id, title: title ?? "t-\(id)", category: category, priority: priority,
        status: status, date: date,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
        completedAt: nil, order: order, archived: archived, dueDate: nil, note: note,
        tags: tags, subtasks: nil, attachments: nil, changelog: nil,
        bugCause: nil, fixPlan: nil, convertedToOptimizationId: nil
    )
}

let todos = [
    makeTodo(id: "a", date: "2026-06-17", order: 2, priority: .low, title: "买牛奶"),
    makeTodo(id: "b", date: "2026-06-17", order: 0, priority: .high, title: "修复登录 bug", note: "和 OAuth 有关"),
    makeTodo(id: "c", date: "2026-06-16", order: 0, category: .bug, status: .done, title: "旧任务"),
    makeTodo(id: "d", date: "2026-06-17", order: 1, status: .inProgress, title: "写周报", tags: ["重要"]),
    makeTodo(id: "archived", date: "2026-06-17", order: 0, archived: true, title: "已归档"),
]

// Default: archived dropped, groups date-descending, within group by order asc.
let groups = TodoFilter.visibleGroups(todos: todos)
expect(groups.count == 2, "two date groups")
expect(groups[0].date == "2026-06-17" && groups[1].date == "2026-06-16", "groups sorted date-descending")
expect(groups[0].todos.map(\.id) == ["b", "d", "a"], "within group sorted by order ascending")
expect(!groups[0].todos.contains { $0.id == "archived" }, "archived todos excluded")

// Priority sort: high → medium → low, then order.
let byPriority = TodoFilter.visibleGroups(todos: todos, sortByPriority: true)
expect(byPriority[0].todos.map(\.id) == ["b", "d", "a"], "priority sort: high(b) > medium(d) > low(a)")

// Category filter.
let bugs = TodoFilter.visibleGroups(todos: todos, category: .bug)
expect(bugs.flatMap(\.todos).allSatisfy { $0.category == .bug }, "category filter keeps only bugs")

// Status filter.
let inProgress = TodoFilter.visibleGroups(todos: todos, status: .inProgress)
expect(inProgress.flatMap(\.todos).map(\.id) == ["d"], "status filter keeps in-progress only")

// Search matches title and note, case-insensitively.
expect(TodoFilter.visibleGroups(todos: todos, search: "OAUTH").flatMap(\.todos).map(\.id) == ["b"],
       "search matches note text, case-insensitive")
expect(TodoFilter.visibleGroups(todos: todos, search: "周报").flatMap(\.todos).map(\.id) == ["d"],
       "search matches title text")

// Tag filter.
expect(TodoFilter.visibleGroups(todos: todos, tag: "重要").flatMap(\.todos).map(\.id) == ["d"],
       "tag filter keeps tagged todos")

print("TodoFilterSortTests passed")
