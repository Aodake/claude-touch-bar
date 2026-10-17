import AppKit

// Claude Code hooks run `ClaudeTouchBar --hook`, which forwards the hook's
// JSON to the running app over a unix socket. Everything except
// PermissionRequest is fire-and-forget (`async` hooks); a permission request
// keeps the connection open until it's answered on the Touch Bar, or released
// with no decision so the app shows its usual dialog.

enum HookPaths {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeTouchBar", isDirectory: true)
    }
    static var socket: String { directory.appendingPathComponent("hooks.sock").path }
    static var log: URL { directory.appendingPathComponent("hooks.log") }
}

/// A short record of what the hooks delivered, for answering "why didn't
/// the bar show up?". Kept under ~200 kB.
enum HookLog {
    private static let queue = DispatchQueue(label: "ClaudeTouchBar.hooklog")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            let url = HookPaths.log
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 200_000,
               let data = try? Data(contentsOf: url) {
                try? data.suffix(100_000).write(to: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}

struct HookEvent {
    let name: String
    let transcriptURL: URL?
    let toolName: String?
    let toolSummary: String?
    let notificationType: String?
    var toolInput: [String: Any]? = nil
    var permissionMode: String? = nil
}

struct ApprovalRequest: Identifiable {
    let id: UUID
    let transcriptURL: URL?
    let toolName: String
    let summary: String
    let canAlwaysAllow: Bool
    let received: Date
}

enum ApprovalDecision {
    case allow, always, deny
}

final class HookServer {
    /// Called on the main thread.
    var onEvent: ((HookEvent) -> Void)?
    var onApprovalsChanged: (([ApprovalRequest]) -> Void)?

    private struct Pending {
        let request: ApprovalRequest
        let fd: Int32
        let suggestions: Any?
    }

    private let lock = NSLock()
    private var pending: [UUID: Pending] = [:]
    private var hold = true
    private var listenFD: Int32 = -1

    /// Whether new permission requests should wait for the Touch Bar. Off
    /// means they pass straight through to the app's own dialog.
    var holdsApprovals: Bool {
        get { lock.withLock { hold } }
        set { lock.withLock { hold = newValue } }
    }

    var approvals: [ApprovalRequest] {
        lock.withLock { pending.values.map(\.request).sorted { $0.received < $1.received } }
    }

    func start() throws {
        signal(SIGPIPE, SIG_IGN)
        try FileManager.default.createDirectory(at: HookPaths.directory, withIntermediateDirectories: true)
        let path = HookPaths.socket
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var addr = HookServer.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 32) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        chmod(path, 0o600)
        listenFD = fd

        let thread = Thread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                DispatchQueue.global(qos: .userInitiated).async { self?.handle(client) }
            }
        }
        thread.name = "ClaudeTouchBar.hooks"
        thread.start()
    }

    func stop() {
        lock.withLock {
            for item in pending.values { close(item.fd) }
            pending.removeAll()
        }
        if listenFD >= 0 { close(listenFD) }
        unlink(HookPaths.socket)
    }

    static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    // MARK: - Connections

    private func handle(_ fd: Int32) {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let data = HookServer.readMessage(fd),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["hook_event_name"] as? String else {
            close(fd)
            return
        }

        if name == "ClaudeTouchBarAnswer" {
            // Test hook: `ClaudeTouchBar --answer allow|always|deny`.
            close(fd)
            let decision: ApprovalDecision
            switch obj["decision"] as? String {
            case "always"?: decision = .always
            case "deny"?: decision = .deny
            default: decision = .allow
            }
            if let oldest = approvals.first { answer(oldest.id, decision) }
            return
        }

        let transcript = (obj["transcript_path"] as? String).map { URL(fileURLWithPath: $0).standardizedFileURL }
        let toolName = obj["tool_name"] as? String
        let summary = HookServer.summary(tool: toolName, input: obj["tool_input"] as? [String: Any])
        let session = (obj["session_id"] as? String).map { String($0.prefix(8)) } ?? "-"
        var details = [name, "session=\(session)"]
        if let mode = obj["permission_mode"] as? String { details.append("mode=\(mode)") }
        if let toolName { details.append("tool=\(toolName)") }
        if let type = obj["notification_type"] as? String { details.append("type=\(type)") }

        // Questions ask "permission" too, but their answer is the card itself.
        let cardTools: Set<String> = ["AskUserQuestion", "mcp__ccd_session__start_session", "mcp__ccd_turn__wrap_up"]

        if name == "PermissionRequest" {
            guard holdsApprovals, !cardTools.contains(toolName ?? "") else {
                HookLog.write((details + ["→ do dialogu v aplikaci (Claude je v popředí nebo schvalování vypnuté)"]).joined(separator: " "))
                close(fd)  // no decision: the app shows its own dialog
                return
            }
            HookLog.write((details + ["→ čeká na Touch Bar"]).joined(separator: " "))
            let suggestions = obj["permission_suggestions"]
            let request = ApprovalRequest(
                id: UUID(), transcriptURL: transcript, toolName: toolName ?? "Nástroj",
                summary: summary ?? "", canAlwaysAllow: (suggestions as? [Any])?.isEmpty == false,
                received: Date())
            lock.withLock { pending[request.id] = Pending(request: request, fd: fd, suggestions: suggestions) }
            publishApprovals()
        } else {
            HookLog.write(details.joined(separator: " "))
            close(fd)
            // The session moved on, so a request we still show was answered
            // in the app's own dialog.
            let movedOn = ["PostToolUse", "PostToolUseFailure", "Stop", "StopFailure", "UserPromptSubmit", "SessionEnd"]
            if movedOn.contains(name), let transcript {
                let stale = approvals.filter { $0.transcriptURL == transcript }
                for request in stale {
                    HookLog.write("Žádost pro \(request.toolName) vyřízena v aplikaci")
                    release(request.id)
                }
            }
        }

        let event = HookEvent(name: name, transcriptURL: transcript, toolName: toolName,
                              toolSummary: summary, notificationType: obj["notification_type"] as? String,
                              toolInput: obj["tool_input"] as? [String: Any],
                              permissionMode: obj["permission_mode"] as? String)
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    func answer(_ id: UUID, _ decision: ApprovalDecision) {
        guard let item = lock.withLock({ pending.removeValue(forKey: id) }) else { return }
        HookLog.write("Odpověď z Touch Baru: \(decision) pro \(item.request.toolName)")
        var body: [String: Any]
        switch decision {
        case .allow:
            body = ["behavior": "allow"]
        case .always:
            body = ["behavior": "allow"]
            if let suggestions = item.suggestions as? [Any], !suggestions.isEmpty {
                body["updatedPermissions"] = suggestions
            }
        case .deny:
            body = ["behavior": "deny", "message": "Zamítnuto z Touch Baru."]
        }
        let reply: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": body]]
        if let data = try? JSONSerialization.data(withJSONObject: reply) {
            data.withUnsafeBytes { _ = write(item.fd, $0.baseAddress, data.count) }
        }
        close(item.fd)
        publishApprovals()
    }

    /// Lets the request fall through to the app's own permission dialog.
    func release(_ id: UUID) {
        guard let item = lock.withLock({ pending.removeValue(forKey: id) }) else { return }
        HookLog.write("Žádost pro \(item.request.toolName) předána dialogu v aplikaci nebo hook skončil")
        close(item.fd)
        publishApprovals()
    }

    func releaseAll() {
        for request in approvals { release(request.id) }
    }

    /// Drops requests whose hook process is gone (interrupted turn, timeout).
    func pruneDisconnected() {
        let gone: [UUID] = lock.withLock {
            pending.filter { _, item in
                var p = pollfd(fd: item.fd, events: Int16(POLLIN), revents: 0)
                return poll(&p, 1, 0) > 0 && (p.revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0
            }.map(\.key)
        }
        for id in gone { release(id) }
    }

    private func publishApprovals() {
        let list = approvals
        DispatchQueue.main.async { self.onApprovalsChanged?(list) }
    }

    // Messages carry a 4-byte length up front, so the client never has to
    // half-close its socket: macOS reports POLLHUP for a half-closed peer,
    // which would make a waiting hook look disconnected.

    static func writeMessage(_ fd: Int32, _ data: Data) {
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        framed.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return }
                offset += n
            }
        }
    }

    static func readMessage(_ fd: Int32) -> Data? {
        guard let header = readExactly(fd, 4) else { return nil }
        let length = header.withUnsafeBytes { Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard length > 0, length < 16_000_000 else { return nil }
        return readExactly(fd, length)
    }

    private static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(capacity: count)
        var buffer = [UInt8](repeating: 0, count: min(count, 65_536))
        while data.count < count {
            let n = read(fd, &buffer, min(buffer.count, count - data.count))
            if n <= 0 { return nil }
            data.append(buffer, count: n)
        }
        return data
    }

    static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    /// A short human description of what the tool is about to do.
    static func summary(tool: String?, input: [String: Any]?) -> String? {
        guard let input else { return nil }
        if let command = input["command"] as? String {
            return command.replacingOccurrences(of: "\n", with: " ")
        }
        for key in ["file_path", "notebook_path", "path"] {
            if let path = input[key] as? String { return URL(fileURLWithPath: path).lastPathComponent }
        }
        if let url = input["url"] as? String { return URL(string: url)?.host ?? url }
        if let pattern = input["pattern"] as? String { return pattern }
        if let description = input["description"] as? String { return description }
        return nil
    }
}

// MARK: - The hook command itself

enum HookClient {
    /// Entry point for `ClaudeTouchBar --hook`. Never fails the hook: if the
    /// app isn't running it exits quietly and Claude carries on as usual.
    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let isPermission = input.range(of: Data("\"PermissionRequest\"".utf8)) != nil
        guard let fd = connectToApp() else { exit(0) }

        HookServer.writeMessage(fd, input)

        if isPermission {
            // Just under the 600 s hook timeout set by the installer.
            var timeout = timeval(tv_sec: 570, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let reply = HookServer.readAll(fd)
            if !reply.isEmpty { FileHandle.standardOutput.write(reply) }
        }
        close(fd)
        exit(0)
    }

    /// `ClaudeTouchBar --answer allow|always|deny` answers the oldest request.
    static func answer(_ decision: String) -> Never {
        guard let fd = connectToApp() else {
            print("Aplikace neběží.")
            exit(1)
        }
        let body = Data(#"{"hook_event_name":"ClaudeTouchBarAnswer","decision":"\#(decision)"}"#.utf8)
        HookServer.writeMessage(fd, body)
        close(fd)
        exit(0)
    }

    private static func connectToApp() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = HookServer.address(HookPaths.socket)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            close(fd)
            return nil
        }
        return fd
    }
}

// MARK: - Registering the hooks in ~/.claude/settings.json

enum HookInstaller {
    private static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    private static let asyncEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Notification", "Stop", "StopFailure", "SessionEnd",
    ]

    private static var command: String {
        "\"\(Bundle.main.executablePath ?? "ClaudeTouchBar")\" --hook"
    }

    private static func isOurs(_ handler: Any) -> Bool {
        guard let handler = handler as? [String: Any], let cmd = handler["command"] as? String else { return false }
        return cmd.contains("ClaudeTouchBar") && cmd.hasSuffix("--hook")
    }

    static var isInstalled: Bool {
        guard let hooks = load()?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]])?.contains { ($0["hooks"] as? [Any])?.contains(where: isOurs) == true } == true
        }
    }

    /// Adds our hooks, leaving every other hook untouched. Backs the file up first.
    static func install() throws {
        var settings = load() ?? [:]
        backup()
        var hooks = removingOurs(from: settings["hooks"] as? [String: Any] ?? [:])
        for event in asyncEvents {
            append(["type": "command", "command": command, "async": true], to: event, in: &hooks)
        }
        append(["type": "command", "command": command, "timeout": 600], to: "PermissionRequest", in: &hooks)
        settings["hooks"] = hooks
        try save(settings)
    }

    static func uninstall() throws {
        guard var settings = load() else { return }
        backup()
        let hooks = removingOurs(from: settings["hooks"] as? [String: Any] ?? [:])
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        try save(settings)
    }

    private static func append(_ handler: [String: Any], to event: String, in hooks: inout [String: Any]) {
        var groups = hooks[event] as? [[String: Any]] ?? []
        groups.append(["matcher": "*", "hooks": [handler]])
        hooks[event] = groups
    }

    private static func removingOurs(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                result[event] = value
                continue
            }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let handlers = group["hooks"] as? [Any] else { return group }
                let remaining = handlers.filter { !isOurs($0) }
                if remaining.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func save(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func backup() {
        let target = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.bak-claudetouchbar")
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: settingsURL, to: target)
    }
}
