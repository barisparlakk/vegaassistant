import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public var succeeded: Bool { status == 0 }
    public var output: String { String(decoding: stdout, as: UTF8.self) }
    public var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ShellError: Error, LocalizedError, Sendable {
    case launchFailed(command: String, reason: String)
    case timedOut(command: String, seconds: Int)
    case failed(command: String, status: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(command, reason): "Couldn't start \(command): \(reason)"
        case let .timedOut(command, seconds): "\(command) didn't finish within \(seconds)s"
        case let .failed(command, status, stderr):
            "\(command) exited with \(status)" + (stderr.nilIfEmpty.map { ": \($0.condensed(limit: 300))" } ?? "")
        }
    }
}

/// Async wrapper around `Process` with timeouts, cancellation and stdin support.
public enum Shell {
    private static let ignoreSIGPIPE: Void = {
        // Writing to a child that already exited must surface as an error, not kill us.
        signal(SIGPIPE, SIG_IGN)
    }()

    public static func run(
        _ executable: URL,
        _ arguments: [String] = [],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> ProcessResult {
        _ = ignoreSIGPIPE
        let runner = ProcessRunner(
            executable: executable,
            arguments: arguments,
            directory: directory,
            environment: environment,
            input: input,
            timeout: timeout
        )
        return try await withTaskCancellationHandler {
            try await runner.run()
        } onCancel: {
            runner.cancel()
        }
    }

    /// Runs and returns stdout, throwing when the exit status isn't zero.
    public static func output(
        _ executable: URL,
        _ arguments: [String] = [],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> String {
        let result = try await run(executable, arguments, in: directory, environment: environment, timeout: timeout)
        guard result.succeeded else {
            throw ShellError.failed(command: executable.lastPathComponent, status: result.status, stderr: result.errorOutput)
        }
        return result.output
    }
}

/// Owns one `Process`. All mutable state is guarded by `lock`.
private final class ProcessRunner: @unchecked Sendable {
    private let process = Process()
    private let input: Data?
    private let timeout: Duration
    private let name: String

    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutClosed = false
    private var stderrClosed = false
    private var terminated = false
    private var finished = false
    private var timedOut = false
    private var cancelled = false
    private var continuation: CheckedContinuation<ProcessResult, any Error>?
    private var readHandles: [FileHandle] = []

    init(executable: URL, arguments: [String], directory: URL?, environment: [String: String]?, input: Data?, timeout: Duration) {
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        if let environment { process.environment = environment }
        self.input = input
        self.timeout = timeout
        self.name = executable.lastPathComponent
    }

    func run() async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            start(continuation)
        }
    }

    private func start(_ continuation: CheckedContinuation<ProcessResult, any Error>) {
        lock.withLock { self.continuation = continuation }
        if lock.withLock({ cancelled }) {
            finish(error: CancellationError())
            return
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = input == nil ? nil : Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe ?? FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStdout: true, handle: handle)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isStdout: false, handle: handle)
        }
        process.terminationHandler = { [weak self] _ in self?.didTerminate() }
        lock.withLock { readHandles = [outPipe.fileHandleForReading, errPipe.fileHandleForReading] }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            finish(error: ShellError.launchFailed(command: name, reason: error.localizedDescription))
            return
        }

        if let input, let inPipe {
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = inPipe.fileHandleForWriting
                try? handle.write(contentsOf: input)
                try? handle.close()
            }
        }

        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            let shouldKill = self.lock.withLock { () -> Bool in
                guard !self.terminated, !self.finished else { return false }
                self.timedOut = true
                return true
            }
            if shouldKill { self.kill() }
        }
    }

    func cancel() {
        let running = lock.withLock { () -> Bool in
            cancelled = true
            return continuation != nil && !terminated
        }
        if running { kill() }
    }

    private func kill() {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.process.isRunning == true { Darwin.kill(pid, SIGKILL) }
        }
    }

    private func consume(_ data: Data, isStdout: Bool, handle: FileHandle) {
        if data.isEmpty {
            handle.readabilityHandler = nil
            lock.withLock {
                if isStdout { stdoutClosed = true } else { stderrClosed = true }
            }
            finishIfComplete()
        } else {
            lock.withLock {
                if isStdout { stdout.append(data) } else { stderr.append(data) }
            }
        }
    }

    private func didTerminate() {
        lock.withLock { terminated = true }
        finishIfComplete()
        // A grandchild may keep the pipes open after the child exits; don't wait for it forever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finishIfComplete(force: true)
        }
    }

    private func finishIfComplete(force: Bool = false) {
        let ready = lock.withLock { terminated && (force || (stdoutClosed && stderrClosed)) }
        guard ready else { return }
        let state = lock.withLock { (timedOut, cancelled) }
        if state.0 {
            finish(error: ShellError.timedOut(command: name, seconds: Int(timeout.components.seconds)))
        } else if state.1 {
            finish(error: CancellationError())
        } else {
            let result = lock.withLock { ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr) }
            finish(result: result)
        }
    }

    private func finish(result: ProcessResult? = nil, error: (any Error)? = nil) {
        let continuation = lock.withLock { () -> CheckedContinuation<ProcessResult, any Error>? in
            guard !finished else { return nil }
            finished = true
            defer { self.continuation = nil }
            return self.continuation
        }
        guard let continuation else { return }
        for handle in lock.withLock({ readHandles }) { handle.readabilityHandler = nil }
        if let error {
            continuation.resume(throwing: error)
        } else if let result {
            continuation.resume(returning: result)
        }
    }
}
