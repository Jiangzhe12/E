import Foundation

// Read-only after init and only used during the single-threaded startup import.
nonisolated(unsafe) private let legacyISOWithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let legacyISOPlain = ISO8601DateFormatter()

/// Result of decoding the TodoList-zhe Electron app's `todo-data.json`.
struct LegacyImportResult: Equatable {
    var todos: [TodoItem]
    var memo: String?
    var memoUpdatedAt: Date?
    var lastOpenDate: String?
    /// Keyed by "MM/dd" week-start, preserved verbatim from the source file.
    var savedReports: [String: String]
    var customTags: [String]
    var templates: [TodoTemplate]
}

/// Pure, AppKit-free decoder that maps the legacy JSON shape onto our native
/// model. Split out of `TodoStore` so it can be unit-tested without sqlite.
enum LegacyTodoDecoder {
    private struct LegacyFile: Decodable {
        let todos: [LegacyTodo]?
        let lastOpenDate: String?
        let savedReports: [String: String]?
        let memo: String?
        let memoUpdatedAt: String?
        let customTags: [String]?
        let templates: [LegacyTemplate]?
    }

    private struct LegacyTodo: Decodable {
        let id: String
        let title: String
        let category: String?
        let priority: String?
        let status: String?
        let date: String?
        let createdAt: String?
        let updatedAt: String?
        let completedAt: String?
        let order: Int?
        let archived: Bool?
        let dueDate: String?
        let note: String?
        let tags: [String]?
        let subtasks: [LegacySubtask]?
        let attachments: [String]?
        let changelog: [LegacyChangeLog]?
        let bugCause: String?
        let fixPlan: String?
        let convertedToOptimizationId: String?
    }

    private struct LegacySubtask: Decodable {
        let id: String?
        let title: String
        let done: Bool?
    }

    private struct LegacyChangeLog: Decodable {
        let timestamp: String?
        let field: String?
        let oldValue: String?
        let newValue: String?
    }

    private struct LegacyTemplate: Decodable {
        let id: String?
        let name: String
        let category: String?
        let priority: String?
        let tags: [String]?
        let subtasks: [String]?
        let note: String?
    }

    /// Decode the file's contents. `today` backfills a missing `date`; `now`
    /// backfills missing timestamps. Throws if the JSON can't be parsed at all.
    static func decode(_ data: Data, today: String, now: Date = Date()) throws -> LegacyImportResult {
        let file = try JSONDecoder().decode(LegacyFile.self, from: data)

        let todos: [TodoItem] = (file.todos ?? []).enumerated().map { index, raw in
            let createdAt = parseISO(raw.createdAt) ?? now
            let updatedAt = parseISO(raw.updatedAt) ?? createdAt
            let status = raw.status.flatMap(TodoStatus.init(rawValue:)) ?? .pending

            var completedAt = parseISO(raw.completedAt)
            // Backfill: old data sometimes marked done without a completedAt.
            if completedAt == nil && status == .done {
                completedAt = updatedAt
            }

            let subtasks: [Subtask]? = raw.subtasks?.map {
                Subtask(id: $0.id ?? UUID().uuidString, title: $0.title, done: $0.done ?? false)
            }
            let changelog: [ChangeLogEntry]? = raw.changelog?.map {
                ChangeLogEntry(
                    timestamp: parseISO($0.timestamp) ?? createdAt,
                    field: $0.field ?? "",
                    oldValue: $0.oldValue,
                    newValue: $0.newValue
                )
            }

            return TodoItem(
                id: raw.id,
                title: raw.title,
                category: raw.category.flatMap(TodoCategory.init(rawValue:)) ?? .feature,
                priority: raw.priority.flatMap(TodoPriority.init(rawValue:)) ?? .medium,
                status: status,
                date: raw.date ?? today,
                createdAt: createdAt,
                updatedAt: updatedAt,
                completedAt: completedAt,
                order: raw.order ?? index,
                archived: raw.archived ?? false,
                dueDate: raw.dueDate,
                note: raw.note,
                tags: raw.tags,
                subtasks: subtasks,
                attachments: raw.attachments,
                changelog: changelog,
                bugCause: raw.bugCause,
                fixPlan: raw.fixPlan,
                convertedToOptimizationId: raw.convertedToOptimizationId
            )
        }

        let templates: [TodoTemplate] = (file.templates ?? []).map {
            TodoTemplate(
                id: $0.id ?? UUID().uuidString,
                name: $0.name,
                category: $0.category.flatMap(TodoCategory.init(rawValue:)) ?? .feature,
                priority: $0.priority.flatMap(TodoPriority.init(rawValue:)) ?? .medium,
                tags: $0.tags,
                subtasks: $0.subtasks,
                note: $0.note
            )
        }

        return LegacyImportResult(
            todos: todos,
            memo: file.memo,
            memoUpdatedAt: parseISO(file.memoUpdatedAt),
            lastOpenDate: file.lastOpenDate,
            savedReports: file.savedReports ?? [:],
            customTags: file.customTags ?? [],
            templates: templates
        )
    }

    /// Parses the legacy timestamps, which carry millisecond fractional seconds
    /// (e.g. `2025-04-13T10:23:45.123Z`) but may occasionally lack them.
    private static func parseISO(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return legacyISOWithFraction.date(from: string) ?? legacyISOPlain.date(from: string)
    }
}
