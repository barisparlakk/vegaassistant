import Foundation

/// JSON Schema for `GeneratedBriefing`, passed to `claude -p --json-schema`.
/// Kept next to the Codable model; `BriefingSchemaTests` checks the two agree.
public enum BriefingSchema {
    public static let json: String = {
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }()

    static var priority: [String: Any] { ["type": "string", "enum": ["high", "medium", "low"]] }
    static var refs: [String: Any] { [
        "type": "array",
        "items": ["type": "string"],
        "description": "Ids of facts from CONTEXT that support this item.",
    ] }
    static var estimate: [String: Any] { ["type": "integer", "minimum": 5, "maximum": 240] }

    static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    static var focusTask: [String: Any] { object([
        "title": ["type": "string", "description": "Starts with a verb; names the concrete thing."],
        "detail": ["type": "string", "description": "One sentence: how, or why it matters."],
        "estimateMinutes": estimate,
        "refs": refs,
    ], required: ["title", "detail", "estimateMinutes", "refs"]) }

    static var item: [String: Any] { object([
        "title": ["type": "string"],
        "detail": ["type": "string"],
        "priority": priority,
        "projectId": ["type": "string"],
        "refs": refs,
        "estimateMinutes": estimate,
    ], required: ["title", "priority", "refs"]) }

    static var section: [String: Any] { object([
        "kind": ["type": "string", "enum": ["overnight", "agenda", "attention", "notes"]],
        "title": ["type": "string"],
        "summary": ["type": "string"],
        "items": ["type": "array", "items": item],
    ], required: ["kind", "title", "items"]) }

    static var nextTask: [String: Any] { object([
        "title": ["type": "string"],
        "projectId": ["type": "string"],
        "priority": priority,
        "estimateMinutes": estimate,
        "reason": ["type": "string"],
    ], required: ["title", "projectId", "priority", "estimateMinutes", "reason"]) }

    static var root: [String: Any] { object([
        "headline": ["type": "string", "description": "One short sentence, at most 100 characters."],
        "focus": object([
            "projectId": ["type": "string", "description": "A project id from CONTEXT.projects."],
            "reason": ["type": "string"],
            "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
            "tasks": ["type": "array", "items": focusTask, "minItems": 1, "maxItems": 3],
        ], required: ["projectId", "reason", "confidence", "tasks"]),
        "sections": ["type": "array", "items": section],
        "nextTasks": ["type": "array", "items": nextTask, "maxItems": 5],
    ], required: ["headline", "focus", "sections", "nextTasks"]) }
}
