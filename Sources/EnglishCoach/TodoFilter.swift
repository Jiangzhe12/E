import Foundation

/// A date-keyed group of todos for the list view.
struct TodoDateGroup: Identifiable, Equatable {
    var id: String { date }
    let date: String
    let todos: [TodoItem]
}

/// Pure filter → group → sort pipeline, ported from the web app's visible-list
/// computation. AppKit-free so it can be unit-tested directly.
enum TodoFilter {
    /// - Parameters:
    ///   - category: `nil` means "all".
    ///   - status: `nil` means "all".
    ///   - search: case-insensitive substring matched against title + note.
    ///   - tag: non-empty filters to todos carrying that tag.
    ///   - sortByPriority: when true, sort each date group by priority (high
    ///     first) then `order`; otherwise by `order` ascending.
    static func visibleGroups(
        todos: [TodoItem],
        category: TodoCategory? = nil,
        status: TodoStatus? = nil,
        search: String = "",
        tag: String = "",
        sortByPriority: Bool = false
    ) -> [TodoDateGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = todos.filter { todo in
            if todo.archived { return false }
            if let category, todo.category != category { return false }
            if let status, todo.status != status { return false }
            if !query.isEmpty {
                let haystack = (todo.title + " " + (todo.note ?? "")).lowercased()
                if !haystack.contains(query) { return false }
            }
            if !tag.isEmpty {
                guard todo.tags?.contains(tag) == true else { return false }
            }
            return true
        }

        let grouped = Dictionary(grouping: filtered, by: { $0.date })

        return grouped.keys.sorted(by: >).map { date in
            let items = grouped[date] ?? []
            let sorted = items.sorted { lhs, rhs in
                if sortByPriority, lhs.priority.sortWeight != rhs.priority.sortWeight {
                    return lhs.priority.sortWeight < rhs.priority.sortWeight
                }
                return lhs.order < rhs.order
            }
            return TodoDateGroup(date: date, todos: sorted)
        }
    }
}
