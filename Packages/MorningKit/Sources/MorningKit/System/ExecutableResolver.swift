import Foundation

/// Finds command-line tools when running from Finder or launchd, where PATH is just
/// `/usr/bin:/bin:/usr/sbin:/sbin` and shell profiles never ran.
public struct ExecutableResolver: Sendable {
    public enum Source: String, Sendable, Codable {
        case override, knownLocation, path, loginShell
    }

    public struct Resolution: Sendable, Hashable {
        public let url: URL
        public let source: Source
    }

    public let paths: MorningPaths

    public init(paths: MorningPaths = MorningPaths()) {
        self.paths = paths
    }

    /// Candidate folders in priority order, besides PATH.
    public func knownDirectories(for name: String) -> [URL] {
        let home = paths.home
        var directories: [URL] = [
            home.appending(path: ".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appending(path: ".npm-global/bin"),
            home.appending(path: ".volta/bin"),
            home.appending(path: ".bun/bin"),
            home.appending(path: "Library/pnpm"),
        ]
        if name == "claude" {
            // The old "local" installer put the launcher here.
            directories.insert(home.appending(path: ".claude/local"), at: 1)
        }
        directories += nvmBinDirectories()
        directories.append(URL(fileURLWithPath: "/usr/bin"))
        return directories
    }

    public func resolve(_ name: String, override: String? = nil) async -> Resolution? {
        if let override = override?.nilIfEmpty {
            let url = paths.expand(override)
            return isExecutable(url) ? Resolution(url: url, source: .override) : nil
        }
        for directory in knownDirectories(for: name) {
            let url = directory.appending(path: name)
            if isExecutable(url) { return Resolution(url: url, source: .knownLocation) }
        }
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for entry in pathEntries {
            let url = URL(fileURLWithPath: String(entry)).appending(path: name)
            if isExecutable(url) { return Resolution(url: url, source: .path) }
        }
        return await resolveWithLoginShell(name)
    }

    /// Last resort: ask the user's interactive login shell, which has their full PATH.
    private func resolveWithLoginShell(_ name: String) async -> Resolution? {
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.nilIfEmpty } ?? "/bin/zsh"
        guard let result = try? await Shell.run(
            URL(fileURLWithPath: shell),
            ["-lic", "command -v \(name)"],
            timeout: .seconds(8)
        ), result.succeeded else { return nil }
        let candidate = result.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
        guard let candidate else { return nil }
        let url = URL(fileURLWithPath: candidate)
        return isExecutable(url) ? Resolution(url: url, source: .loginShell) : nil
    }

    private func nvmBinDirectories() -> [URL] {
        let versions = paths.home.appending(path: ".nvm/versions/node")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: versions.path) else { return [] }
        // Newest version first; "v22.3.0" sorts correctly with numeric comparison.
        return entries
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appending(path: "\($0)/bin") }
    }

    private func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.resolvingSymlinksInPath().path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }
}

/// Resolved tools for one collection run.
public struct Toolbox: Sendable {
    public var git: URL?
    public var gh: URL?
    public var claude: URL?

    public init(git: URL? = nil, gh: URL? = nil, claude: URL? = nil) {
        self.git = git
        self.gh = gh
        self.claude = claude
    }

    public static func resolve(settings: MorningSettings, paths: MorningPaths) async -> Toolbox {
        let resolver = ExecutableResolver(paths: paths)
        async let git = resolver.resolve("git", override: settings.gitPath)
        async let gh = resolver.resolve("gh", override: settings.ghPath)
        async let claude = resolver.resolve("claude", override: settings.claudePath)
        return await Toolbox(git: git?.url, gh: gh?.url, claude: claude?.url)
    }
}
