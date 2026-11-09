import Foundation
import MorningKit

/// morning-cli — the headless half of Morning. The LaunchAgent runs
/// `generate --trigger scheduled --if-needed`; the other commands are for inspection.

let usage = """
usage: morning-cli <command> [options]

commands:
  generate    Collect, ask Claude, validate and save today's briefing
      --trigger <manual|scheduled>  recorded in the briefing (default: manual)
      --if-needed                   do nothing if today's briefing already exists
      --dry-run                     print the prompt instead of calling Claude
      --model <name>                override the model from Settings
  context     Collect everything and print it (the input to the briefing)
      --json                        print JSON instead of a readable summary
  list        List saved briefings
  show [date] Print a briefing as Markdown (default: latest)
      --json                        print the stored JSON
  schedule <install|uninstall|status>
              Daily LaunchAgent that runs `generate --trigger scheduled --if-needed`
      --time <HH:MM>                override the time from Settings
  news        Print today's news feed
      --refresh                     search again now (one web-search run)
      --dry-run                     print the news prompt instead of searching
      --json                        print JSON
  hook <install|uninstall|status|snippet>
              Claude Code Stop hook (merged into ~/.claude/settings.json with a backup)
  doctor      Check tools, permissions and paths
  help        Show this help

common options:
  --since <24h|3d|ISO-8601>  window start (default: since the last briefing, max \(MorningSettings.default.maxLookbackDays) days)
  --request-access           allow Calendar/Reminders permission prompts
"""

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

struct Options {
    var command = "help"
    var argument: String?
    var since: String?
    var json = false
    var requestAccess = false
    var trigger = Briefing.Trigger.manual
    var ifNeeded = false
    var dryRun = false
    var model: String?
    var time: String?
    var refresh = false

    init(_ arguments: [String]) throws {
        var remaining = arguments[...]
        if let first = remaining.first, !first.hasPrefix("-") {
            command = first
            remaining = remaining.dropFirst()
        }
        func value(for flag: String) throws -> String {
            guard let value = remaining.popFirst() else { throw CLIError(description: "\(flag) needs a value") }
            return value
        }
        while let item = remaining.popFirst() {
            switch item {
            case "--since": since = try value(for: item)
            case "--json": json = true
            case "--request-access": requestAccess = true
            case "--if-needed": ifNeeded = true
            case "--dry-run": dryRun = true
            case "--model": model = try value(for: item)
            case "--time": time = try value(for: item)
            case "--refresh": refresh = true
            case "--trigger":
                let raw = try value(for: item)
                guard let parsed = Briefing.Trigger(rawValue: raw) else { throw CLIError(description: "--trigger must be manual or scheduled") }
                trigger = parsed
            case "-h", "--help": command = "help"
            default:
                guard !item.hasPrefix("-"), argument == nil else { throw CLIError(description: "unknown option \(item)") }
                argument = item
            }
        }
    }
}

struct Environment {
    let paths = MorningPaths()
    var settings: MorningSettings

    init(options: Options) {
        settings = SettingsStore(paths: paths).load()
        if let model = options.model { settings.claudeModel = model }
    }

    func period(_ options: Options, now: Date = .now) throws -> Period? {
        guard let since = options.since else { return nil }
        guard let from = LookbackPolicy.parseSince(since, now: now) else {
            throw CLIError(description: "can't read --since \(since); use 24h, 3d, 90m or an ISO 8601 date")
        }
        return Period(from: from, to: now)
    }
}

// MARK: - Commands

func runGenerate(_ options: Options) async throws {
    let env = Environment(options: options)
    let generator = BriefingGenerator(settings: env.settings, paths: env.paths, mayRequestPermissions: options.requestAccess)
    let progress = ProgressPrinter(enabled: isatty(STDERR_FILENO) == 1)
    let period = try env.period(options) ?? generator.nextPeriod()

    if options.dryRun {
        let (_, prompt) = await generator.preparePrompt(period: period) { progress.handle($0) }
        progress.clear()
        print("=== SYSTEM (\(prompt.system.count) chars)\n\(prompt.system)\n")
        print("=== USER (\(prompt.user.count) chars, ~\(prompt.user.utf8.count / 4) tokens)\n\(prompt.user)\n")
        print("=== SCHEMA (\(prompt.schema.count) chars)\n\(prompt.schema)")
        return
    }

    if options.trigger == .scheduled, try await handOffToAppIfNeeded(options: options, env: env) {
        return
    }

    do {
        let briefing = try await generator.generate(trigger: options.trigger, period: period, skipIfExists: options.ifNeeded) {
            progress.handle($0)
        }
        progress.clear()
        if options.trigger == .scheduled, hostingApp() != nil {
            // Let the app post the "briefing ready" notification (it launches hidden if needed).
            _ = await AppHandoff.open(AppHandoff.readyURL(id: briefing.id))
        }
        if options.json {
            FileHandle.standardOutput.write(try JSONCoding.prettyEncoder.encode(briefing))
            print()
        } else {
            print(BriefingMarkdown.render(briefing))
            let seconds = Double(briefing.durationMs) / 1000
            log("Saved \(env.paths.abbreviate(BriefingStore(paths: env.paths).url(for: briefing.id).path)) in \(String(format: "%.1f", seconds)) s (\(briefing.attempts) attempt\(briefing.attempts == 1 ? "" : "s")).")
            for repair in briefing.repairs { log("  repaired: \(repair)") }
        }
    } catch let error as GeneratorError {
        progress.clear()
        if case .alreadyGeneratedToday = error, options.ifNeeded {
            log(error.localizedDescription + " Nothing to do.")
            return
        }
        throw error
    }
}

/// This executable's real location, even when run through a symlink on PATH
/// (where argv[0] is just "morning-cli").
func currentExecutable() -> URL {
    (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
}

/// The Morning.app this helper is embedded in, if any.
func hostingApp() -> URL? {
    let executable = currentExecutable()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? app : nil
}

/// Calendar and Reminders permission belong to Morning.app; a helper started by launchd can't
/// show the prompt. When access is missing, the app does the scheduled run instead.
func handOffToAppIfNeeded(options: Options, env: Environment) async throws -> Bool {
    let settings = env.settings
    let missingAccess = (settings.isEnabled(.calendar) && !EventKitService.calendarAccess.isGranted)
        || (settings.isEnabled(.reminders) && !EventKitService.remindersAccess.isGranted)
    guard missingAccess, hostingApp() != nil else { return false }
    if options.ifNeeded, BriefingStore(paths: env.paths).exists(Briefing.id(for: .now)) {
        log("Today's briefing already exists. Nothing to do.")
        return true
    }
    log("\(Date.now.formatted(.iso8601)) Calendar/Reminders access belongs to Vega.app — handing the run to the app.")
    if await AppHandoff.open(AppHandoff.generateURL(trigger: options.trigger, ifNeeded: options.ifNeeded)) {
        return true
    }
    log("Couldn't reach Vega.app; generating here without calendar data.")
    return false
}

func runSchedule(_ options: Options) async throws {
    let paths = MorningPaths()
    var settings = SettingsStore(paths: paths).load()
    let manager = LaunchAgentManager(paths: paths)
    switch options.argument ?? "status" {
    case "install":
        if let time = options.time {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
                throw CLIError(description: "--time must look like 07:00")
            }
            settings.briefingHour = parts[0]
            settings.briefingMinute = parts[1]
            try SettingsStore(paths: paths).save(settings)
        }
        let executable = currentExecutable()
        try await manager.install(executable: executable, hour: settings.briefingHour, minute: settings.briefingMinute)
        print("Installed \(paths.abbreviate(paths.launchAgentPlist.path)) — runs daily at \(String(format: "%02d:%02d", settings.briefingHour, settings.briefingMinute)).")
    case "uninstall":
        try await manager.uninstall()
        print("Removed the scheduler.")
    case "status":
        guard manager.isInstalled else {
            print("Not installed. Run `morning-cli schedule install`.")
            return
        }
        let loaded = await manager.isLoaded()
        print("Installed (\(loaded ? "loaded" : "not loaded")) — daily at \(String(format: "%02d:%02d", settings.briefingHour, settings.briefingMinute))")
        print("Runs: \(manager.installedExecutable ?? "?")")
        print("Log:  \(paths.abbreviate(paths.logs.appending(path: "scheduler.log").path))")
    default:
        throw CLIError(description: "schedule takes install, uninstall or status")
    }
}

func runNews(_ options: Options) async throws {
    let env = Environment(options: options)
    let id = Briefing.id(for: .now)
    if options.dryRun {
        let facts = BriefingStore(paths: env.paths).latest()?.facts
        let prompt = NewsPrompt.build(settings: env.settings, facts: facts, now: .now)
        print("=== SYSTEM\n\(prompt.system)\n\n=== USER\n\(prompt.user)\n\n=== SCHEMA\n\(prompt.schema)")
        return
    }
    let feed: NewsFeed
    if options.refresh {
        log("Searching the web for news… (one claude run, usually 30–90 s)")
        feed = try await NewsGenerator(settings: env.settings, paths: env.paths).refresh()
    } else if let saved = NewsStore(paths: env.paths).latest(onOrBefore: id) {
        feed = saved
    } else {
        throw CLIError(description: "no news yet — run `morning-cli news --refresh` or generate a briefing")
    }
    if options.json {
        FileHandle.standardOutput.write(try JSONCoding.prettyEncoder.encode(feed))
        print()
        return
    }
    for category in feed.categories {
        print("\n\(category.label)")
        if category.items.isEmpty { print("  (nothing notable)") }
        for (index, item) in category.items.enumerated() {
            let date = item.publishedAt.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            print(String(format: "  %02d ", index + 1) + item.title)
            print("     \(item.source)\(date) — \(item.url)")
            if let relevance = item.relevance { print("     ↳ \(relevance)") }
        }
    }
}

func runHook(_ options: Options) throws {
    let installer = HookInstaller(paths: MorningPaths())
    switch options.argument ?? "status" {
    case "install":
        let backup = try installer.install()
        print("Stop hook installed: \(installer.paths.abbreviate(installer.paths.hookScript.path))")
        if let backup { print("Backup of your settings: \(installer.paths.abbreviate(backup.path))") }
    case "uninstall":
        let backup = try installer.uninstall()
        print(backup == nil ? "The hook wasn't installed." : "Stop hook removed. Backup: \(installer.paths.abbreviate(backup!.path))")
    case "status":
        print(installer.isInstalled ? "Installed." : "Not installed. Run `morning-cli hook install`.")
    case "snippet":
        print(installer.settingsSnippet)
    default:
        throw CLIError(description: "hook takes install, uninstall, status or snippet")
    }
}

func runContext(_ options: Options) async throws {
    let env = Environment(options: options)
    let generator = BriefingGenerator(settings: env.settings, paths: env.paths)
    let period = try env.period(options) ?? generator.nextPeriod()

    let progress = ProgressPrinter(enabled: !options.json && isatty(STDERR_FILENO) == 1)
    let pipeline = CollectionPipeline(settings: env.settings, paths: env.paths, mayRequestPermissions: options.requestAccess)
    let result = await pipeline.run(period: period) { progress.handle(.collecting($0)) }
    progress.clear()

    if options.json {
        FileHandle.standardOutput.write(try JSONCoding.prettyEncoder.encode(ContextPayload(facts: result.facts, reports: result.reports)))
        print()
    } else {
        print(ContextRenderer(paths: env.paths).render(result))
    }
}

func runList(_ options: Options) {
    let store = BriefingStore(paths: MorningPaths())
    let summaries = store.summaries()
    guard !summaries.isEmpty else {
        print("No briefings yet. Run `morning-cli generate`.")
        return
    }
    let time = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    for summary in summaries {
        let focus = summary.focusProjectName.map { "[\($0)] " } ?? ""
        let headline = summary.isFallback ? "(text fallback)" : (summary.headline ?? "")
        print("\(summary.id)  \(summary.generatedAt.formatted(time))  \(summary.trigger == .scheduled ? "auto" : "    ")  \(focus)\(headline)")
    }
}

func runShow(_ options: Options) throws {
    let store = BriefingStore(paths: MorningPaths())
    let briefing: Briefing? = if let id = options.argument { try store.load(id) } else { store.latest() }
    guard let briefing else { throw CLIError(description: options.argument.map { "no briefing for \($0)" } ?? "no briefings yet") }
    if options.json {
        FileHandle.standardOutput.write(try JSONCoding.prettyEncoder.encode(briefing))
        print()
    } else {
        print(BriefingMarkdown.render(briefing))
    }
}

struct ContextPayload: Encodable {
    let facts: BriefingFacts
    let reports: [CollectorReport]
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - Entry point

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    switch options.command {
    case "generate": try await runGenerate(options)
    case "context": try await runContext(options)
    case "list": runList(options)
    case "show": try runShow(options)
    case "news": try await runNews(options)
    case "schedule": try await runSchedule(options)
    case "hook": try runHook(options)
    case "doctor": await runDoctor()
    case "help": print(usage)
    default: throw CLIError(description: "unknown command \(options.command)\n\n\(usage)")
    }
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    log("morning-cli: \(message)")
    exit(1)
}
