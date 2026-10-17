import Foundation

struct Tokens {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cost: Double = 0

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    /// Everything the model read: fresh input plus cache traffic.
    var totalIn: Int { input + cacheRead + cacheWrite }
    var total: Int { totalIn + output }

    static func += (lhs: inout Tokens, rhs: Tokens) {
        lhs.input += rhs.input
        lhs.output += rhs.output
        lhs.cacheRead += rhs.cacheRead
        lhs.cacheWrite5m += rhs.cacheWrite5m
        lhs.cacheWrite1h += rhs.cacheWrite1h
        lhs.cost += rhs.cost
    }
}

enum Activity {
    case working, waiting, done, idle
}

/// Everything the Touch Bar and the detail window need, computed in one pass.
struct Snapshot {
    var hasSession = false
    var activity: Activity = .idle
    var turnStart: Date?
    var turnEnd: Date?
    var model: String?
    var contextUsed = 0
    var contextWindow = 1_000_000
    var session = Tokens()
    var fiveHours = Tokens()
    var today = Tokens()
    var title: String?
    var project: String?
    /// Full path of the session's working folder.
    var cwd: String?
    var lastActivity: Date?
    var sessionURL: URL?
    /// Permission mode from the hooks, e.g. "Auto"; filled in by the app.
    var mode: String?
    /// Git state of the Push repository; filled in by the app.
    var git: GitStatus?
    /// Progress through Claude's task list; filled in by the app.
    var plan: PlanProgress?
    /// Sessions active in the last few hours, newest first.
    var sessions: [SessionInfo] = []
    var isAutoSelected = true
    /// Tool currently running, as reported by the PreToolUse hook.
    var tool: String?
    /// A permission request waiting for an answer; filled in by the app.
    var approval: ApprovalRequest?
    /// Estimated $ per 5 minutes over the last hour, oldest first.
    var burn: [Double] = []
    /// Estimated $ per hour over the last 24 hours, oldest first.
    var hourly: [Double] = []
    /// This calendar week (from Monday) and this month.
    var week = Tokens()
    var month = Tokens()
    /// Estimated $ per day over the last 30 days, oldest first.
    var daily: [Double] = []
    /// Minutes today in which Claude did something (5-minute resolution).
    var activeMinutes = 0
    /// Files Claude edited or wrote in the shown session.
    var changedFiles: [String] = []

    /// Estimated $ spent over the last hour.
    var hourlyRate: Double { burn.reduce(0, +) }
    var waitingCount: Int { sessions.filter { $0.activity == .waiting }.count }

    var activeSessionCount: Int {
        sessions.filter { $0.activity == .working || $0.activity == .waiting }.count
    }

    var contextFraction: Double {
        contextWindow > 0 ? min(1, Double(contextUsed) / Double(contextWindow)) : 0
    }

    var modelName: String { Pricing.info(for: model).shortName }
}

struct SessionInfo: Identifiable {
    let url: URL
    let title: String
    let activity: Activity
    let lastActivity: Date
    var id: URL { url }
}

/// What the Claude Code hooks last told us about a session.
struct HookState {
    var activity: Activity
    var time: Date
    var tool: String?
    /// The session's permission mode as the picker names it ("Auto"…).
    var mode: String?
}

/// Branch and uncommitted changes of the session's folder.
struct GitStatus {
    var branch: String
    var changes: Int
    var ahead: Int
}

private struct UsageEvent {
    let time: Date
    let tokens: Tokens
}

private enum EntryKind {
    case none, prompt, toolResult, assistantTool, assistantStreaming, assistantEnd, interrupted
}

/// Parse state for one transcript file, advanced incrementally as it grows.
private final class FileState {
    let url: URL
    var offset: UInt64 = 0
    var remainder = Data()
    var mtime = Date.distantPast
    /// Keyed by message id + request id: Claude Code writes one line per
    /// content block, each repeating the same usage.
    var events: [String: UsageEvent] = [:]
    /// Paths of files Claude edited or wrote in this transcript.
    var changedFiles = Set<String>()
    var lastKind = EntryKind.none
    var lastEntryTime: Date?
    var turnStart: Date?
    var turnEnd: Date?
    var contextUsed = 0
    var model: String?
    var title: String?
    var cwd: String?

    init(url: URL) { self.url = url }
}

/// Reads the session transcripts Claude Code writes to ~/.claude/projects —
/// the Code tab of the Claude desktop app writes them too.
final class UsageStore {
    let root: URL
    private var files: [URL: FileState] = [:]
    private let queue = DispatchQueue(label: "ClaudeTouchBar.usage", qos: .utility)

    private static let markers: [Data] = [
        Data("\"type\":\"assistant\"".utf8),
        Data("\"type\":\"user\"".utf8),
        Data("\"type\":\"custom-title\"".utf8),
    ]

    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.root = root.standardizedFileURL
    }

    /// `selected` pins a session (nil picks automatically); `hooks` are the
    /// latest hook states keyed by transcript URL.
    func refresh(selected: URL?, hooks: [URL: HookState], _ completion: @escaping (Snapshot) -> Void) {
        queue.async {
            let snapshot = self.scan(selected: selected, hooks: hooks)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    /// Synchronous variant for `--dump`.
    func scanNow() -> Snapshot {
        queue.sync { scan(selected: nil, hooks: [:]) }
    }

    // MARK: - Scanning

    private func scan(selected: URL?, hooks: [URL: HookState]) -> Snapshot {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        var calendar = Calendar.current
        calendar.firstWeekday = 2  // weeks start on Monday
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? dayStart
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: dayStart) ?? dayStart
        let windowStart = min(dayStart, fiveHoursAgo, now.addingTimeInterval(-24 * 3600),
                              weekStart, monthStart, thirtyDaysAgo)

        let found = listTranscripts()
        let topLevel = found.filter { isTopLevel($0.url) }

        // A session is as fresh as its newest file, subagents included.
        var sessionActivity: [URL: Date] = [:]
        for file in found {
            let owner = owningSession(of: file.url)
            sessionActivity[owner] = max(sessionActivity[owner] ?? .distantPast, file.mtime)
        }
        let newest = topLevel
            .map { ($0.url, sessionActivity[$0.url] ?? $0.mtime) }
            .max { $0.1 < $1.1 }?.0

        for file in found {
            let owner = owningSession(of: file.url)
            if file.mtime >= windowStart || owner == newest || owner == selected {
                update(file.url, mtime: file.mtime, size: file.size)
            }
        }
        let live = Set(found.map(\.url))
        files = files.filter { live.contains($0.key) }

        var snap = Snapshot()

        // Totals across every session, deduplicated by message id.
        var allEvents: [String: UsageEvent] = [:]
        for state in files.values {
            allEvents.merge(state.events) { _, new in new }
        }
        snap.burn = Array(repeating: 0, count: 12)
        snap.hourly = Array(repeating: 0, count: 24)
        snap.daily = Array(repeating: 0, count: 30)
        var activeBuckets = Set<Int>()
        for event in allEvents.values {
            if event.time >= fiveHoursAgo { snap.fiveHours += event.tokens }
            if event.time >= dayStart { snap.today += event.tokens }
            let age = now.timeIntervalSince(event.time)
            if age >= 0 && age < 3600 { snap.burn[11 - Int(age / 300)] += event.tokens.cost }
            if age >= 0 && age < 24 * 3600 { snap.hourly[23 - Int(age / 3600)] += event.tokens.cost }
            if event.time >= weekStart { snap.week += event.tokens }
            if event.time >= monthStart { snap.month += event.tokens }
            if event.time >= thirtyDaysAgo,
               let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: event.time), to: dayStart).day,
               (0..<30).contains(days) {
                snap.daily[29 - days] += event.tokens.cost
            }
            if event.time >= dayStart { activeBuckets.insert(Int(event.time.timeIntervalSince(dayStart) / 300)) }
        }
        snap.activeMinutes = activeBuckets.count * 5

        // Recent sessions, each with its best-known activity.
        let recentLimit = now.addingTimeInterval(-3 * 3600)
        var infos: [SessionInfo] = []
        for file in topLevel {
            let last = sessionActivity[file.url] ?? file.mtime
            guard last >= recentLimit || file.url == newest || file.url == selected,
                  let state = files[file.url] else { continue }
            let (activity, _) = resolve(state, lastActivity: last, hook: hooks[file.url], now: now)
            let title = state.title
                ?? state.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? file.url.deletingPathExtension().lastPathComponent
            infos.append(SessionInfo(url: file.url, title: title, activity: activity, lastActivity: last))
        }
        snap.sessions = infos.sorted { $0.lastActivity > $1.lastActivity }

        // Pinned session if it still exists, otherwise whichever needs you
        // (waiting first), otherwise the most recent one.
        let chosen: URL?
        if let selected, files[selected] != nil {
            chosen = selected
            snap.isAutoSelected = false
        } else {
            chosen = snap.sessions.first { $0.activity == .waiting }?.url ?? newest
        }

        guard let sessionURL = chosen, let main = files[sessionURL] else { return snap }
        let lastActivity = sessionActivity[sessionURL] ?? main.mtime
        snap.hasSession = true
        snap.sessionURL = sessionURL
        snap.lastActivity = lastActivity
        snap.turnStart = main.turnStart
        snap.turnEnd = main.turnEnd
        snap.model = main.model
        snap.contextUsed = main.contextUsed
        snap.contextWindow = Pricing.info(for: main.model).contextWindow
        snap.title = main.title
        snap.project = main.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        snap.cwd = main.cwd
        snap.mode = hooks[sessionURL]?.mode

        var sessionEvents: [String: UsageEvent] = [:]
        for (url, state) in files where owningSession(of: url) == sessionURL {
            sessionEvents.merge(state.events) { _, new in new }
        }
        for event in sessionEvents.values { snap.session += event.tokens }
        var touched = Set<String>()
        for (url, state) in files where owningSession(of: url) == sessionURL { touched.formUnion(state.changedFiles) }
        snap.changedFiles = touched.sorted()

        let (activity, tool) = resolve(main, lastActivity: lastActivity, hook: hooks[sessionURL], now: now)
        snap.activity = activity
        snap.tool = tool
        return snap
    }

    /// Hooks are exact, so they win while they're at least as fresh as the
    /// transcript. An interrupt fires no hook, which the transcript catches.
    private func resolve(_ state: FileState, lastActivity: Date, hook: HookState?, now: Date) -> (Activity, String?) {
        let guess = activity(for: state.lastKind, age: now.timeIntervalSince(lastActivity))
        guard let hook, hook.time >= (state.lastEntryTime ?? .distantPast).addingTimeInterval(-10) else {
            return (guess, nil)
        }
        let age = now.timeIntervalSince(hook.time)
        switch hook.activity {
        case .working where age > 1800, .done where age > 1800:
            return (.idle, nil)
        case .working:
            return (.working, hook.tool)
        default:
            return (hook.activity, nil)
        }
    }

    private func activity(for kind: EntryKind, age: TimeInterval) -> Activity {
        switch kind {
        case .assistantEnd, .interrupted:
            return age > 1800 ? .idle : .done
        case .prompt, .toolResult, .assistantStreaming:
            // The model can think for a while without writing anything.
            return age < 900 ? .working : .idle
        case .assistantTool:
            // A tool call with no result yet: either running or waiting for
            // your approval in the app.
            if age < 25 { return .working }
            return age < 1800 ? .waiting : .idle
        case .none:
            return .idle
        }
    }

    private struct Found {
        let url: URL
        let mtime: Date
        let size: UInt64
    }

    private func listTranscripts() -> [Found] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [Found] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            result.append(Found(url: url.standardizedFileURL,
                                mtime: values.contentModificationDate ?? .distantPast,
                                size: UInt64(values.fileSize ?? 0)))
        }
        return result
    }

    /// `<root>/<project>/<session>.jsonl`
    private func isTopLevel(_ url: URL) -> Bool {
        url.deletingLastPathComponent().deletingLastPathComponent() == root
    }

    /// Subagent transcripts live in `<project>/<session>/subagents/*.jsonl`;
    /// map them back to `<project>/<session>.jsonl`.
    private func owningSession(of url: URL) -> URL {
        if isTopLevel(url) { return url }
        var dir = url.deletingLastPathComponent()
        while dir.path.count > root.path.count {
            let parent = dir.deletingLastPathComponent()
            if parent == root { break }
            if parent.deletingLastPathComponent() == root {
                return parent.appendingPathComponent(dir.lastPathComponent + ".jsonl")
            }
            dir = parent
        }
        return url
    }

    // MARK: - Incremental parsing

    private func update(_ url: URL, mtime: Date, size: UInt64) {
        let state: FileState
        if let existing = files[url], size >= existing.offset {
            state = existing
            if existing.mtime == mtime && existing.offset == size { return }
        } else {
            state = FileState(url: url)
            files[url] = state
        }
        state.mtime = mtime

        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        do {
            try fh.seek(toOffset: state.offset)
        } catch {
            return
        }
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return }
        state.offset += UInt64(data.count)

        var buffer = state.remainder
        buffer.append(data)
        var lineStart = buffer.startIndex
        while let newline = buffer[lineStart...].firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[lineStart..<newline]
            if !line.isEmpty { handle(line: Data(line), in: state) }
            lineStart = buffer.index(after: newline)
        }
        state.remainder = Data(buffer[lineStart...])
    }

    private func handle(line: Data, in state: FileState) {
        guard Self.markers.contains(where: { line.range(of: $0) != nil }),
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "custom-title":
            if let title = obj["customTitle"] as? String, !title.isEmpty { state.title = title }
        case "assistant":
            handleAssistant(obj, in: state)
        case "user":
            handleUser(obj, in: state)
        default:
            break
        }
    }

    private func handleAssistant(_ obj: [String: Any], in state: FileState) {
        guard let message = obj["message"] as? [String: Any] else { return }
        let model = message["model"] as? String
        if model == "<synthetic>" { return }
        let time = date(obj["timestamp"]) ?? state.mtime
        state.lastEntryTime = time

        // Files Claude touches through its editing tools.
        for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
            guard let name = block["name"] as? String, ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(name),
                  let input = block["input"] as? [String: Any],
                  let path = (input["file_path"] ?? input["notebook_path"]) as? String else { continue }
            state.changedFiles.insert(path)
        }

        if let usage = message["usage"] as? [String: Any], let model {
            let info = Pricing.info(for: model)
            var t = Tokens()
            t.input = usage["input_tokens"] as? Int ?? 0
            t.output = usage["output_tokens"] as? Int ?? 0
            t.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let created = usage["cache_creation_input_tokens"] as? Int ?? 0
            if let split = usage["cache_creation"] as? [String: Any] {
                t.cacheWrite1h = split["ephemeral_1h_input_tokens"] as? Int ?? 0
                t.cacheWrite5m = split["ephemeral_5m_input_tokens"] as? Int ?? max(0, created - t.cacheWrite1h)
            } else {
                t.cacheWrite5m = created
            }
            let speedFactor = (usage["speed"] as? String) == "fast" ? 2.0 : 1.0
            t.cost = speedFactor * (
                Double(t.input) * info.input
                + Double(t.output) * info.output
                + Double(t.cacheRead) * info.cacheRead
                + Double(t.cacheWrite5m) * info.cacheWrite5m
                + Double(t.cacheWrite1h) * info.cacheWrite1h
            ) / 1_000_000

            let id = (message["id"] as? String ?? UUID().uuidString) + (obj["requestId"] as? String ?? "")
            state.events[id] = UsageEvent(time: time, tokens: t)
            state.contextUsed = t.input + t.cacheRead + created
            state.model = model
        }

        switch message["stop_reason"] as? String {
        case "tool_use"?:
            state.lastKind = .assistantTool
        case nil:
            state.lastKind = .assistantStreaming
        default:
            state.lastKind = .assistantEnd
            state.turnEnd = time
        }
    }

    private func handleUser(_ obj: [String: Any], in state: FileState) {
        if obj["isMeta"] as? Bool == true { return }
        if let cwd = obj["cwd"] as? String { state.cwd = cwd }
        guard let message = obj["message"] as? [String: Any] else { return }
        let time = date(obj["timestamp"]) ?? state.mtime
        state.lastEntryTime = time

        var texts: [String] = []
        var hasToolResult = false
        if let text = message["content"] as? String {
            texts = [text]
        } else if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                switch block["type"] as? String {
                case "tool_result"?: hasToolResult = true
                case "text"?: texts.append(block["text"] as? String ?? "")
                default: break
                }
            }
        }

        if texts.contains(where: { $0.hasPrefix("[Request interrupted") }) {
            state.lastKind = .interrupted
            state.turnEnd = time
        } else if hasToolResult {
            state.lastKind = .toolResult
        } else if texts.contains(where: { $0.hasPrefix("<command-") || $0.hasPrefix("<local-command") }) {
            // Slash-command bookkeeping, not a prompt to the model.
            return
        } else {
            state.lastKind = .prompt
            state.turnStart = time
            state.turnEnd = nil
        }
    }

    private func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }
}
