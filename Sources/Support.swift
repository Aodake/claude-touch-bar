import AppKit

enum Layout: Int, CaseIterable {
    case compact, overview, minimal

    var title: String {
        switch self {
        case .compact: return L("Kompaktní", "Compact")
        case .overview: return L("Přehled", "Overview")
        case .minimal: return "Minimal"
        }
    }

    var next: Layout { Layout(rawValue: (rawValue + 1) % Layout.allCases.count) ?? .compact }
}

/// The app's UI language; `.system` is Czech when macOS prefers Czech.
enum Lang: String, CaseIterable {
    case system, cs, en

    var title: String {
        switch self {
        case .system: return L("Podle systému", "System")
        case .cs: return "Čeština"
        case .en: return "English"
        }
    }
}

/// The Czech or the English text, whichever the UI language is.
func L(_ czech: String, _ english: String) -> String {
    Settings.czech ? czech : english
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var language: Lang {
        get { Lang(rawValue: defaults.string(forKey: "language") ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: "language")
            czech = resolveCzech()
        }
    }

    /// Cached, since every Touch Bar redraw asks.
    private(set) static var czech = resolveCzech()

    private static func resolveCzech() -> Bool {
        switch language {
        case .cs: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("cs") ?? false
        }
    }

    static var layout: Layout {
        get { Layout(rawValue: defaults.integer(forKey: "layout")) ?? .compact }
        set { defaults.set(newValue.rawValue, forKey: "layout") }
    }

    /// Show the bar on its own whenever the Claude app comes to the front.
    static var autoShow: Bool {
        get { bool("autoShow", default: true) }
        set { defaults.set(newValue, forKey: "autoShow") }
    }

    /// Answer permission requests from the Touch Bar while you're elsewhere.
    static var approvals: Bool {
        get { bool("approvals", default: true) }
        set { defaults.set(newValue, forKey: "approvals") }
    }

    /// Also offer requests on the Touch Bar while Claude is in front. The
    /// app shows its own dialog at the same time, so either answer works.
    static var approvalsInClaude: Bool {
        get { bool("approvalsInClaude", default: true) }
        set { defaults.set(newValue, forKey: "approvalsInClaude") }
    }

    /// Pop the bar up briefly when a session finishes while you're elsewhere.
    static var popOnDone: Bool {
        get { bool("popOnDone", default: true) }
        set { defaults.set(newValue, forKey: "popOnDone") }
    }

    /// Use the whole Touch Bar (no Control Strip); ⤓ shrinks back to the Mac's.
    static var fullWidth: Bool {
        get { bool("fullWidth", default: true) }
        set { defaults.set(newValue, forKey: "fullWidth") }
    }

    /// The repository the Push button watches, and the name it shows.
    static var pushRepo: String {
        get { defaults.string(forKey: "pushRepo") ?? "" }
        set { defaults.set(newValue, forKey: "pushRepo") }
    }

    static var pushName: String {
        get { defaults.string(forKey: "pushName") ?? "" }
        set { defaults.set(newValue, forKey: "pushName") }
    }

    /// Mirror Claude's cards (new-session offers, questions, next steps).
    static var cards: Bool {
        get { bool("cards", default: true) }
        set { defaults.set(newValue, forKey: "cards") }
    }

    static var sound: Bool {
        get { bool("sound", default: true) }
        set { defaults.set(newValue, forKey: "sound") }
    }

    /// Daily spending budget in USD; 0 turns it off.
    static var dailyBudget: Double {
        get { max(0, defaults.double(forKey: "dailyBudget")) }
        set { defaults.set(max(0, newValue), forKey: "dailyBudget") }
    }

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }
}

/// Presses keys in the Claude app. Needs the Accessibility permission, which
/// macOS ties to the app's signature (a rebuild asks again).
enum KeySender {
    static let escape: CGKeyCode = 53
    static let n: CGKeyCode = 45

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility settings.
    @discardableResult
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static let v: CGKeyCode = 9
    static let returnKey: CGKeyCode = 36

    static func send(_ key: CGKeyCode, flags: CGEventFlags = []) {
        guard requestTrust() else { return }
        ClaudeApp.activate()
        // Give the app a moment to come forward before the keystroke lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { press(key, flags: flags) }
    }

    /// Types `text` into Claude's message box and sends it. Goes through the
    /// clipboard (restored afterwards) so diacritics arrive intact.
    @discardableResult
    static func sendMessage(_ text: String) -> Bool {
        guard requestTrust() else { return false }
        ClaudeApp.activate()
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            press(v, flags: .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                press(returnKey)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    pasteboard.clearContents()
                    if let previous { pasteboard.setString(previous, forType: .string) }
                }
            }
        }
        return true
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

enum Git {
    /// `git status` of a folder; nil when it isn't a repository.
    static func status(at path: String) -> GitStatus? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "status", "--porcelain=v1", "--branch"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A huge repository shouldn't stall the refresh.
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0,
              let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return nil }

        let lines = text.split(separator: "\n").map(String.init)
        guard let header = lines.first, header.hasPrefix("## ") else { return nil }
        // "## main...origin/main [ahead 2]" or "## main" or "## HEAD (no branch)"
        let info = header.dropFirst(3)
        let branch = info.components(separatedBy: "...").first?.components(separatedBy: " ").first ?? "?"
        var ahead = 0
        if let range = info.range(of: "ahead ") {
            ahead = Int(info[range.upperBound...].prefix { $0.isNumber }) ?? 0
        }
        return GitStatus(branch: branch, changes: lines.count - 1, ahead: ahead)
    }
}

extension Snapshot {
    /// Hours the daily budget lasts at the last hour's pace; nil without a
    /// budget or without recent spending.
    func budgetRunway(_ budget: Double) -> Double? {
        guard budget > 0 else { return nil }
        let remaining = budget - today.cost
        if remaining <= 0 { return 0 }
        let perHour = burn.reduce(0, +)
        return perHour > 0.01 ? remaining / perHour : nil
    }
}

extension Format {
    /// "45 min", "2 h 15 min".
    static func minutes(_ total: Int) -> String {
        total < 60 ? "\(total) min" : "\(total / 60) h \(total % 60) min"
    }

    /// "~40 min", "~2,5 h" ("~2.5 h"), "došel" ("used up").
    static func runway(_ hours: Double) -> String {
        if hours <= 0 { return L("došel", "used up") }
        if hours < 1 { return "~\(max(1, Int(hours * 60))) min" }
        if hours < 10 { return "~" + String(format: "%.1f", hours).replacingOccurrences(of: ".", with: L(",", ".")) + " h" }
        return "~\(Int(hours)) h"
    }
}

enum Sounds {
    static func play(_ name: String) {
        guard Settings.sound else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

enum ClaudeApp {
    static let bundleID = "com.anthropic.claudefordesktop"

    static func activate() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Start at login through a per-user LaunchAgent; works for an ad-hoc signed
/// app living outside /Applications.
enum LaunchAtLogin {
    private static let label = "local.ClaudeTouchBar"
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if !enabled {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        (plist as NSDictionary).write(to: plistURL, atomically: true)
    }
}

enum Format {
    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<10_000: return String(format: "%.1fk", Double(n) / 1_000)
        case ..<1_000_000: return "\(n / 1_000)k"
        case ..<10_000_000 where n % 1_000_000 == 0: return "\(n / 1_000_000)M"
        case ..<10_000_000: return String(format: "%.1fM", Double(n) / 1_000_000)
        default: return "\(n / 1_000_000)M"
        }
    }

    static func cost(_ usd: Double) -> String {
        switch usd {
        case ..<10: return String(format: "$%.2f", usd)
        case ..<100: return String(format: "$%.1f", usd)
        default: return String(format: "$%.0f", usd)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))" + L(" %", "%")
    }
}

enum Palette {
    static let claude = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    static let done = NSColor.systemGreen
    static let waiting = NSColor.systemYellow
    static let warning = NSColor.systemOrange
    static let danger = NSColor.systemRed
    static let dim = NSColor(white: 1, alpha: 0.55)
    static let normal = NSColor(white: 0.88, alpha: 1)

    /// Neutral until the context fills up, so orange and red stand out.
    static func context(_ fraction: Double) -> NSColor {
        if fraction >= 0.9 { return danger }
        if fraction >= 0.7 { return warning }
        return normal
    }
}
