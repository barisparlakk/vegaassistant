# Morning

A personal daily briefing for macOS. Every morning Morning reads what happened since yesterday — Claude Code sessions, git commits, open pull requests — plus today's calendar and reminders, and asks Claude which project deserves your attention and what to do next.

It runs Claude Code in headless mode (`claude -p`) on your **Claude subscription**. It never uses an API key and sends nothing anywhere except the briefing prompt to Claude.

The interface is calm and keyboard-first. It follows the system light or dark mode and uses the system font. Today opens with a glass orb, a greeting and the day's headline, then the focus card, overnight work, news and the decisions waiting on you.

- **Today** — the day's priority (headline, project, estimate, why) with up to three checkable tasks and a focus-block timer; `overnight.log` with what happened per project and a `DONE` / `NEEDS_YOU` / `FAILED` status; the agenda with a now-line; `attention` items with Terminal / editor / GitHub buttons; and the top news.
- **History** — every past briefing by date, in the same layout.
- **Projects** — a table of every repository: branch, last touched, 14-day activity line, and state (active, idle, or a deadline like `T-18d`).
- **News** — recent stories per category, found with Claude Code's web search, with a line when a story relates to one of your projects.
- **Menu bar** — the priority, next event, top news and regenerate.

## Requirements

- macOS 15 or later (Liquid Glass styling on macOS 26+)
- Xcode 26 or later, with the license accepted (`sudo xcodebuild -license accept`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [Claude Code](https://docs.claude.com/en/docs/claude-code), signed in to a Claude subscription
- Optional: the [GitHub CLI](https://cli.github.com) (`gh`), signed in, for pull requests and issues

## Build and install

```bash
xcodegen generate
```

```bash
xcodebuild -project Morning.xcodeproj -scheme Morning -configuration Release -derivedDataPath .build/xcode build
```

```bash
ditto .build/xcode/Build/Products/Release/Morning.app /Applications/Morning.app
```

Then open Morning from `/Applications`. The command-line helper lives inside the app at `Morning.app/Contents/MacOS/morning-cli`. To use it from a shell:

```bash
ln -sf /Applications/Morning.app/Contents/MacOS/morning-cli /opt/homebrew/bin/morning-cli
```

`Morning.xcodeproj` is generated from `project.yml`; edit `project.yml`, not the project, and run `xcodegen generate` again.

### Signing (recommended)

The project signs ad hoc by default. macOS remembers Calendar, Reminders and Desktop-folder permission per signature, so an ad-hoc build may ask again after each rebuild. To keep permissions across rebuilds, sign with your free Apple ID team: in `project.yml` set

```yaml
CODE_SIGN_IDENTITY: "Apple Development"
CODE_SIGN_STYLE: Automatic
DEVELOPMENT_TEAM: "YOURTEAMID"
```

and regenerate the project.

## First run

1. **Sign in Claude Code.** Morning uses the standalone `claude` CLI, which keeps its own login (separate from the Claude desktop app):

   ```bash
   claude auth login
   ```

   `morning-cli doctor` or Settings › Claude shows whether it's signed in.

2. **Generate a briefing.** Click *Generate today's briefing* (or press ⌘R). The first run asks for a few permissions — see below.

3. **Turn on automation** in Settings › Automation:
   - **Scheduled briefing** installs the daily LaunchAgent.
   - **Claude Code Stop hook** records when each Claude Code session ends.
   - **Notifications** — allow them to hear when the morning briefing is ready.
   - Settings › General › **Open at login** keeps the menu bar item around.

## Permissions

| Permission | Why | When it's asked |
|---|---|---|
| Desktop / Documents folder | Your repositories may live there (Morning scans `~/dev`, `~/Developer`, `~/Projects` and `~/Desktop` by default) | The first time Morning scans those folders |
| Calendar | Today's events for the agenda | First generation, or *Allow access…* on the Today screen / in Settings |
| Reminders | Reminders due today or overdue | Same as Calendar |
| Notifications | "Your morning briefing is ready" | When you install the scheduler, or in Settings |

Everything is optional. A source that isn't available is shown as *not connected* — the briefing says it doesn't know, rather than pretending your day is empty. Manage permissions later in System Settings › Privacy & Security.

## Scheduled briefings (LaunchAgent)

Install from Settings › Automation, or from a shell:

```bash
morning-cli schedule install --time 07:00
```

This writes `~/Library/LaunchAgents/com.barisparlak.Morning.scheduler.plist` and loads it with `launchctl`. Every day at the chosen time launchd runs:

```
Morning.app/Contents/MacOS/morning-cli generate --trigger scheduled --if-needed
```

- **Sleep:** if the Mac was asleep at the scheduled time, launchd runs the job as soon as it wakes.
- **Shutdown:** if the Mac was off, Morning generates the briefing the next time the app launches.
- **`--if-needed`** makes a run do nothing when today's briefing already exists.
- **Calendar permission:** a helper started by launchd can't show the macOS permission prompt. When it doesn't have Calendar/Reminders access, it hands the run to Morning.app (via a `morning://generate` link that launches the app hidden), which has the permissions.
- When the run finishes, the app posts the notification. Clicking it opens Today.
- Changing the time in Settings reinstalls the agent. Moving the app re-points it automatically on the next launch.

Check or remove it:

```bash
morning-cli schedule status
```

```bash
morning-cli schedule uninstall
```

The log is at `~/Library/Logs/Morning/scheduler.log`.

## Claude Code Stop hook

The hook appends one line to `~/.morning/log.jsonl` whenever a Claude Code session stops, so the briefing knows exactly when you finished working on something. It's a small POSIX shell script with no dependencies (`~/.morning/hooks/morning-stop-hook.sh`); it always exits 0, so it can never block or fail a session, and it ignores Morning's own headless runs.

Install from Settings › Automation, or:

```bash
morning-cli hook install
```

Installing **backs up** `~/.claude/settings.json` to `settings.json.morning-backup-<timestamp>`, then adds Morning's entry to `hooks.Stop` and leaves everything else as it was — including any Stop hooks you already have. If the file isn't valid JSON, Morning refuses to touch it. `morning-cli hook uninstall` removes only Morning's entry (again with a backup).

To add it by hand instead, print the snippet and merge it into `~/.claude/settings.json`:

```bash
morning-cli hook snippet
```

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/Users/you/.morning/hooks/morning-stop-hook.sh" } ] }
    ]
  }
}
```

The entry only works if the script exists at that path. `morning-cli hook install` writes it; if you add the entry by hand, copy the script from `HookInstaller.script` in `Packages/MorningKit/Sources/MorningKit/System/HookInstaller.swift` and make it executable.

## Keyboard

| Where | Keys |
|---|---|
| Everywhere | `⌘1` today · `⌘2` history · `⌘3` projects · `⌘4` news · `⌘,` settings · `⌘R` regenerate |
| Today | `j`/`k` or arrows move · `space` check a task · `↵` start a focus block / expand a row / open · `⌫` skip a task · `t` `e` `g` open the selected item in Terminal, editor or GitHub · `s` save a story |
| Projects | `j`/`k` move · `↵` details · `/` filter · `t` `e` `g` open · `esc` close details |
| History | `j`/`k` move between days |
| News | `j`/`k` move · `↵` open (marks read) · `s` save · `←`/`→` or `1`–`9` categories · `r` refresh |

Focus blocks and skipped tasks are kept in the app only; checked tasks are stored with the briefing day.

## News

Alongside each briefing, Morning runs a second headless call that may use one tool, Claude Code's **WebSearch** (pre-approved with `--allowedTools`; nothing else is available to it). It looks for recent stories in your categories and returns JSON that Morning validates: only `https` links, no duplicates, at most N per category, and a `relevance` line only when it names one of your real projects. The feed is saved next to the briefing as `briefings/YYYY-MM-DD.news.json`. A news failure never blocks the briefing; it shows as a source line.

Configure it in Settings › News: on/off, items per category, and the categories themselves (a label plus, in plain words, what to look for). Defaults: ai+tech, research (arXiv cs.AI/cs.LG), türkiye, science. Refresh any time with `r` in the News view or:

```bash
morning-cli news --refresh
```

It adds one subscription call with web search, usually 30–90 seconds, running at the same time as the briefing call.

## How a briefing is made

```
Collectors ──▶ Prompt builder ──▶ claude -p ──▶ Validator ──▶ Store ──▶ App / menu bar / CLI
```

1. **Collect** (in parallel, each optional — Settings › Sources):
   - **Claude Code sessions** — `~/.claude/projects/*/*.jsonl` since the last briefing: your prompts, files edited, notable shell actions.
   - **Stop-hook log** — `~/.morning/log.jsonl`.
   - **Git** — every repository under your folders: branch, uncommitted and unpushed work, stale branches, commits since the last briefing, 14 days of activity.
   - **GitHub** — via `gh`: your open PRs (with checks and review state), review requests, assigned issues.
   - **Calendar** and **Reminders** — via EventKit.
   - **Notes** — open items in `TODO.md` / `NOTES.md` at each repository root.
2. **Flag** — deterministic rules turn repo and GitHub state into *attention* items (failing checks, review requests, uncommitted or unpushed work, stale branches).
3. **Ask Claude** — a compact, id-tagged summary (usually 4–15k tokens) goes to `claude -p --output-format json --json-schema …` with tools disabled, MCP servers off, your Claude settings and hooks ignored, and session persistence off.
4. **Validate** — the answer is decoded and checked against the facts: the focus project must exist, references must point at real commits/sessions/PRs, estimates are clamped, duplicates removed. If it can't be used, Claude gets one retry with the problems listed; if that fails too, the answer is saved and shown as text.
5. **Save** — `briefings/YYYY-MM-DD.json` holds the collected facts *and* Claude's answer. The timeline, agenda, sparklines and buttons are drawn from the facts, so hashes, times and links are always real; Claude only writes the words and refers to facts by id.

The "since" window starts where the previous briefing ended (or 24 hours ago, never more than 4 days). Regenerating the same day keeps that day's window.

### Your subscription, never an API key

Before running `claude`, Morning removes every `ANTHROPIC_*` variable (including `ANTHROPIC_API_KEY`) and every `CLAUDE*` variable a parent Claude Code session may have set (except `CLAUDE_CONFIG_DIR`), and sets `MORNING_GENERATING=1`. The prompt is sent on stdin from a private working folder (`~/Library/Application Support/Morning/run`). Each briefing is one `claude -p` call (two if the first answer doesn't validate).

## Command-line helper

```
morning-cli generate [--trigger manual|scheduled] [--if-needed] [--dry-run] [--model NAME] [--since 24h|3d|ISO-8601]
morning-cli context  [--json] [--since …]        collected data, without calling Claude
morning-cli news [--refresh] [--dry-run] [--json] today's news feed (refresh runs the web search)
morning-cli list                                saved briefings
morning-cli show [YYYY-MM-DD] [--json]          a briefing as Markdown or JSON
morning-cli schedule install|uninstall|status [--time HH:MM]
morning-cli hook install|uninstall|status|snippet
morning-cli doctor                              tools, Claude login, permissions, paths, repositories
```

`generate --dry-run` prints the exact system prompt, context and JSON Schema that would be sent.

## Settings

Settings live in `~/Library/Application Support/Morning/settings.json`, shared by the app and the helper:

- repository folders, search depth, and whether to include folders where you used Claude Code
- briefing time and accent color
- which sources are on, and which calendars to include
- Claude model (`sonnet`, `opus`, `haiku`, …) and a custom path to `claude`
- extra instructions appended to every briefing prompt (tone, language, priorities)

Morning finds `claude` even when launched from Finder or launchd, where `PATH` is minimal: it checks `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, npm/Volta/Bun/pnpm and nvm locations, then your login shell. Set a custom path in Settings › Claude if yours is elsewhere.

## Files

| Path | Contents |
|---|---|
| `~/Library/Application Support/Morning/briefings/` | One JSON file per day; earlier versions of a regenerated day in `.revisions/` |
| `~/Library/Application Support/Morning/settings.json` | Settings |
| `~/Library/Application Support/Morning/state.json` | Last run, last error |
| `~/Library/Application Support/Morning/checks.json` | Which focus tasks you checked off |
| `~/Library/Application Support/Morning/briefings/*.news.json` | News feed for each day |
| `~/Library/Application Support/Morning/news-state.json` | Read and saved stories |
| `~/Library/Logs/Morning/scheduler.log` | Output of scheduled runs |
| `~/Library/LaunchAgents/com.barisparlak.Morning.scheduler.plist` | The scheduler |
| `~/.morning/log.jsonl`, `~/.morning/hooks/` | Stop-hook log and script |

Settings › Data › *Open data folder* opens the briefings folder. There's no telemetry and no network access other than `claude` and `gh`.

## Troubleshooting

- **Start with `morning-cli doctor`.** It shows which `claude`, `git` and `gh` were found, whether Claude Code is signed in, permission status, paths and the repositories it sees.
- **"Claude Code isn't signed in"** — run `claude auth login` in Terminal. The desktop app's login doesn't count.
- **"Claude usage limit reached"** — the briefing waits for your subscription's limit to reset; regenerate later.
- **No calendar events** — check Settings › Sources › Calendar, and that the right calendars are on.
- **A scheduled run didn't happen** — `morning-cli schedule status`, then `~/Library/Logs/Morning/scheduler.log`. launchd only runs agents while you're logged in.
- **The answer shows as text** — Claude's answer didn't match the format twice; the reason is at the bottom of the text. Regenerate.

## Development

```bash
cd Packages/MorningKit && swift test
```

- `Packages/MorningKit` — collectors, prompt builder, Claude runner, validator, stores, scheduler and hook installers, plus the `morning-cli` sources. Builds and tests with plain SwiftPM.
- `App/` — the SwiftUI app. `DesignSystem/DS.swift` holds every spacing, radius, size, color (light and dark values), type and motion token; `DSComponents.swift` the shared panels, rows, tags, buttons and skeletons. Views use tokens, not raw numbers.
- Every view has `#Preview`s with realistic sample data (`MockData`).
- Launch the app with `--demo` (or `MORNING_DEMO=1`) to use sample data instead of your own.

## Uninstall

```bash
morning-cli schedule uninstall
```

```bash
morning-cli hook uninstall
```

```bash
rm -rf /Applications/Morning.app ~/Library/Application\ Support/Morning ~/Library/Logs/Morning ~/.morning
```
