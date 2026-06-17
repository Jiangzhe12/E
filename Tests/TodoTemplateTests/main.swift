import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAILED: \(message)") }
}

let template = TodoTemplate(
    id: "tmpl",
    name: "发布检查",
    category: .optimization,
    priority: .high,
    tags: ["发布", "检查"],
    subtasks: ["跑测试", "更新 README", "打 tag"],
    note: "上线前过一遍"
)

let todo = makeTodoFromTemplate(template, todoId: "new", date: "2026-06-17", now: Date(timeIntervalSince1970: 1000))

expect(todo.title == "发布检查", "template name becomes the title")
expect(todo.category == .optimization && todo.priority == .high, "category and priority carried")
expect(todo.note == "上线前过一遍", "note carried")
expect(todo.tags == ["发布", "检查"], "tags carried")
expect(todo.status == .pending, "new todo starts pending")
expect(todo.date == "2026-06-17", "date applied")
expect(todo.attachments == nil, "attachments are not carried from template")

expect(todo.subtasks?.count == 3, "all subtask titles materialised")
expect(todo.subtasks?.map(\.title) == ["跑测试", "更新 README", "打 tag"], "subtask titles preserved in order")
expect(todo.subtasks?.allSatisfy { !$0.done } == true, "materialised subtasks start undone")
expect(Set(todo.subtasks?.map(\.id) ?? []).count == 3, "each subtask gets a distinct id")

// A template with no subtasks → nil subtasks (not an empty array sentinel).
let bare = TodoTemplate(id: "b", name: "空模板", category: .feature, priority: .medium, tags: nil, subtasks: nil, note: nil)
let bareTodo = makeTodoFromTemplate(bare, date: "2026-06-17")
expect(bareTodo.subtasks == nil, "no subtasks stays nil")
expect(bareTodo.tags == nil && bareTodo.note == nil, "absent optional fields stay nil")

print("TodoTemplateTests passed")
