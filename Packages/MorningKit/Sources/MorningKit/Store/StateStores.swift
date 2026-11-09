import Foundation

/// What the scheduler and the app need to remember between runs.
public struct RunState: Codable, Sendable, Hashable {
    /// End of the window covered by the last saved briefing — the start of the next one.
    public var lastSuccessfulRun: Date?
    public var lastAttemptAt: Date?
    public var lastError: String?
    public var consecutiveFailures: Int

    public init(lastSuccessfulRun: Date? = nil, lastAttemptAt: Date? = nil, lastError: String? = nil, consecutiveFailures: Int = 0) {
        self.lastSuccessfulRun = lastSuccessfulRun
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.consecutiveFailures = consecutiveFailures
    }
}

public struct RunStateStore: Sendable {
    public let paths: MorningPaths

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    public func load() -> RunState {
        guard let data = try? Data(contentsOf: paths.stateFile),
              let state = try? JSONCoding.decoder.decode(RunState.self, from: data)
        else { return RunState() }
        return state
    }

    public func save(_ state: RunState) throws {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        try JSONCoding.prettyEncoder.encode(state).write(to: paths.stateFile, options: .atomic)
    }

    public func recordSuccess(coveringUntil end: Date, at now: Date = .now) {
        var state = load()
        state.lastSuccessfulRun = end
        state.lastAttemptAt = now
        state.lastError = nil
        state.consecutiveFailures = 0
        try? save(state)
    }

    public func recordFailure(_ message: String, at now: Date = .now) {
        var state = load()
        state.lastAttemptAt = now
        state.lastError = message
        state.consecutiveFailures += 1
        try? save(state)
    }
}

/// Check marks on focus tasks, per briefing day. Keyed by `FocusTask.checkKey`, so a task
/// stays checked when the day is regenerated and the model proposes it again.
public struct TaskCheckStore: Sendable {
    public let paths: MorningPaths

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    var file: URL { paths.appSupport.appending(path: "checks.json") }

    public func checkedKeys(for briefingID: String) -> Set<String> {
        Set(all()[briefingID] ?? [])
    }

    public func isChecked(_ task: GeneratedBriefing.FocusTask, in briefingID: String) -> Bool {
        checkedKeys(for: briefingID).contains(task.checkKey)
    }

    public func setChecked(_ checked: Bool, task: GeneratedBriefing.FocusTask, in briefingID: String) throws {
        var everything = all()
        var keys = Set(everything[briefingID] ?? [])
        if checked { keys.insert(task.checkKey) } else { keys.remove(task.checkKey) }
        everything[briefingID] = keys.isEmpty ? nil : keys.sorted()
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        try JSONCoding.prettyEncoder.encode(everything).write(to: file, options: .atomic)
    }

    private func all() -> [String: [String]] {
        guard let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return value
    }
}

/// Cross-process mutex (app + LaunchAgent) around generation, using `flock`.
/// The lock is released when the holder exits, even if it crashes.
public final class GenerationLock: Sendable {
    private let descriptor: Int32

    public struct Busy: Error, LocalizedError, Sendable {
        public var errorDescription: String? { "A briefing is already being generated." }
    }

    public init(paths: MorningPaths) throws {
        try FileManager.default.createDirectory(at: paths.appSupport, withIntermediateDirectories: true)
        let path = paths.appSupport.appending(path: "generate.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw Busy()
        }
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
