import Foundation

/// Checks a model answer against the facts it was given.
///
/// *Problems* make the answer unusable and trigger a retry (bad JSON, a focus project that
/// doesn't exist). *Repairs* are fixed in place and recorded (unknown references dropped,
/// estimates clamped, extra tasks trimmed) — the briefing is still worth showing.
public enum BriefingValidator {
    public struct Outcome: Sendable {
        public var briefing: GeneratedBriefing?
        public var problems: [String]
        public var repairs: [String]

        public var isValid: Bool { briefing != nil && problems.isEmpty }
    }

    static let maxHeadline = 160
    static let maxFocusTasks = 3
    static let maxNextTasks = 5
    static let estimateRange = 5...240

    /// Decodes the reply (structured output first, then JSON inside the text) and validates it.
    public static func evaluate(_ reply: ClaudeReply, facts: BriefingFacts) -> Outcome {
        guard let draft = decode(reply) else {
            return Outcome(briefing: nil, problems: ["The answer was not a JSON object matching the schema."], repairs: [])
        }
        return validate(draft, facts: facts)
    }

    static func decode(_ reply: ClaudeReply) -> GeneratedBriefing? {
        let decoder = JSONDecoder()
        if let data = reply.structuredOutput, let draft = try? decoder.decode(GeneratedBriefing.self, from: data) {
            return draft
        }
        guard let json = extractJSONObject(from: reply.text) else { return nil }
        return try? decoder.decode(GeneratedBriefing.self, from: Data(json.utf8))
    }

    /// Finds the outermost `{…}` — tolerates code fences or a stray sentence around the JSON.
    static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }

    public static func validate(_ input: GeneratedBriefing, facts: BriefingFacts) -> Outcome {
        var draft = input
        var problems: [String] = []
        var repairs: [String] = []
        let projectIDs = Set(facts.projects.map(\.id))
        let knownRefs = facts.referenceableIDs
        var droppedRefs = Set<String>()

        func cleanRefs(_ refs: [String]) -> [String] {
            refs.filter { ref in
                let known = knownRefs.contains(ref)
                if !known { droppedRefs.insert(ref) }
                return known
            }
            .uniqued(by: { $0 })
        }

        func clampEstimate(_ minutes: Int, label: String) -> Int {
            let clamped = min(max(minutes, estimateRange.lowerBound), estimateRange.upperBound)
            if clamped != minutes { repairs.append("Clamped the estimate for “\(label)” from \(minutes) to \(clamped) min.") }
            return clamped
        }

        // Headline
        draft.headline = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.headline.isEmpty { problems.append("headline is empty.") }
        if draft.headline.count > maxHeadline {
            draft.headline = draft.headline.condensed(limit: maxHeadline)
            repairs.append("Shortened the headline.")
        }

        // Focus
        if !projectIDs.isEmpty, !projectIDs.contains(draft.focus.projectID) {
            let sample = projectIDs.sorted().prefix(12).joined(separator: ", ")
            problems.append("focus.projectId \"\(draft.focus.projectID)\" is not a project id from CONTEXT. Use one of: \(sample).")
        }
        if draft.focus.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("focus.reason is empty.")
        }
        var tasks = draft.focus.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        if tasks.count > maxFocusTasks {
            repairs.append("Kept the first \(maxFocusTasks) of \(tasks.count) focus tasks.")
            tasks = Array(tasks.prefix(maxFocusTasks))
        }
        if tasks.isEmpty, !projectIDs.isEmpty { problems.append("focus.tasks must contain 1–3 tasks with titles.") }
        draft.focus.tasks = tasks.enumerated().map { index, task in
            var task = task
            task.id = "t\(index + 1)"
            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.estimateMinutes = clampEstimate(task.estimateMinutes, label: task.title)
            task.refs = cleanRefs(task.refs)
            return task
        }

        // Sections: canonical order, no empty ones, known projects and refs only.
        let order = GeneratedBriefing.Section.Kind.allCases
        draft.sections = draft.sections
            .compactMap { section -> GeneratedBriefing.Section? in
                var section = section
                section.items = section.items.compactMap { item in
                    var item = item
                    item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !item.title.isEmpty else { return nil }
                    if let project = item.projectID, !projectIDs.contains(project) { item.projectID = nil }
                    item.refs = cleanRefs(item.refs)
                    item.estimateMinutes = item.estimateMinutes.map { clampEstimate($0, label: item.title) }
                    item.detail = item.detail?.nilIfEmpty
                    return item
                }
                section.summary = section.summary?.nilIfEmpty
                return section.items.isEmpty && section.summary == nil ? nil : section
            }
            .uniqued(by: \.kind)
            .sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }

        // Next tasks: known projects only, and nothing already said by the focus or attention.
        let validNextTasks = draft.nextTasks.filter { projectIDs.contains($0.projectID) && !$0.title.isEmpty }
        if validNextTasks.count < draft.nextTasks.count {
            repairs.append("Dropped \(draft.nextTasks.count - validNextTasks.count) next task(s) with an unknown project.")
        }
        let coveredProjects = Set([draft.focus.projectID] + (draft.section(.attention)?.items.compactMap(\.projectID) ?? []))
        let freshNextTasks = validNextTasks.filter { !coveredProjects.contains($0.projectID) }
        if freshNextTasks.count < validNextTasks.count {
            repairs.append("Dropped \(validNextTasks.count - freshNextTasks.count) next task(s) repeating the focus or attention items.")
        }
        draft.nextTasks = freshNextTasks.prefix(maxNextTasks).map { task in
            var task = task
            task.estimateMinutes = clampEstimate(task.estimateMinutes, label: task.title)
            return task
        }

        // Ids that leaked into prose become what a person would write.
        var rewrites = 0
        func readable(_ text: String) -> String {
            let (result, count) = humanizeIDs(in: text, facts: facts)
            rewrites += count
            return result
        }
        draft.headline = readable(draft.headline)
        draft.focus.reason = readable(draft.focus.reason)
        draft.focus.tasks = draft.focus.tasks.map { task in
            var task = task
            task.title = readable(task.title)
            task.detail = readable(task.detail)
            return task
        }
        draft.sections = draft.sections.map { section in
            var section = section
            section.title = readable(section.title)
            section.summary = section.summary.map(readable)
            section.items = section.items.map { item in
                var item = item
                item.title = readable(item.title)
                item.detail = item.detail.map(readable)
                return item
            }
            return section
        }
        draft.nextTasks = draft.nextTasks.map { task in
            var task = task
            task.title = readable(task.title)
            task.reason = readable(task.reason)
            return task
        }
        if rewrites > 0 { repairs.append("Rewrote \(rewrites) id(s) that appeared in the text.") }

        if !droppedRefs.isEmpty {
            repairs.append("Dropped unknown references: \(droppedRefs.sorted().prefix(8).joined(separator: ", "))\(droppedRefs.count > 8 ? " …" : "").")
        }
        return Outcome(briefing: problems.isEmpty ? draft : nil, problems: problems, repairs: repairs)
    }

    /// `commit:8f9a61f6f8` → `8f9a61f`, `repo:daybase` → `daybase`, `pr:o/r#12` → `#12`,
    /// `branch:app/feat/x` → `feat/x`; ids with no short form (attention, sessions…) are removed.
    static func humanizeIDs(in text: String, facts: BriefingFacts) -> (String, Int) {
        let pattern = /\b(?<kind>commit|repo|dir|session|pr|issue|attn|note|event|reminder|branch):(?<value>[A-Za-z0-9_\-.\/#:]+)/
        var count = 0
        var result = text.replacing(pattern) { match -> String in
            count += 1
            var value = String(match.output.value)
            var trailing = ""
            while let last = value.last, ".:".contains(last) {
                trailing = String(last) + trailing
                value.removeLast()
            }
            let kind = String(match.output.kind)
            let replacement: String = switch kind {
            case "commit": String(value.prefix(7))
            case "repo", "dir": facts.project("\(kind):\(value)")?.name ?? value.split(separator: "/").last.map(String.init) ?? value
            case "pr", "issue": value.split(separator: "#").last.map { "#\($0)" } ?? value
            case "branch": value.split(separator: "/", maxSplits: 1).last.map(String.init) ?? value
            default: ""
            }
            return replacement + trailing
        }
        guard count > 0 else { return (text, 0) }
        // Tidy what removed ids leave behind: "see , and" / "( )" / double spaces.
        result = result
            .replacing(/\(\s*[,;]?\s*\)/, with: "")
            .replacing(/\s+([,.;:])/, with: { "\($0.output.1)" })
            .replacing(/,\s*,/, with: ",")
            .replacing(/\ {2,}/, with: " ")
            .trimmingCharacters(in: .whitespaces)
        return (result, count)
    }

    /// Best-effort reading for the markdown fallback: decodable but invalid answers are still
    /// rendered from their structure rather than shown as raw JSON.
    public static func fallbackMarkdown(for reply: ClaudeReply?, facts: BriefingFacts, problems: [String]) -> String {
        var text: String
        if let reply, let draft = decode(reply) {
            text = BriefingMarkdown.render(draft, facts: facts)
        } else if let raw = reply?.text.nilIfEmpty {
            text = raw
        } else {
            text = "Claude didn't return a usable briefing."
        }
        if !problems.isEmpty {
            text += "\n\n---\n_Shown as text because the answer didn't pass validation: "
                + problems.joined(separator: " ") + "_"
        }
        return text
    }
}
