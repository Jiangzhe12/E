import Foundation

/// Daily carry-over, ported from TodoList-zhe's `carryOverTodos`. Runs when the
/// app is first opened on a new day:
/// - archived todos are never touched;
/// - completed todos from a past date are auto-archived;
/// - incomplete todos from a past date are pulled forward to today.
///
/// Pure and AppKit-free so it can be unit-tested in isolation. Comparison is on
/// the "YYYY-MM-DD" string (lexicographic == chronological), never on parsed
/// `Date`s, to stay timezone-safe.
enum TodoCarryOver {
    /// Returns the full list with carry-over applied. `now` is the timestamp
    /// stamped onto any todo that changes (defaults to current time).
    static func apply(_ todos: [TodoItem], today: String, now: Date = Date()) -> [TodoItem] {
        todos.map { todo in
            guard !todo.archived else { return todo }
            guard todo.date < today else { return todo }

            var updated = todo
            if todo.status == .done {
                updated.archived = true
            } else {
                updated.date = today
            }
            updated.updatedAt = now
            return updated
        }
    }
}
