import Foundation

/// Daily token totals kept in ~/Library/Application Support/ClaudeTouchBar,
/// so the all-time figure survives Claude Code deleting old transcripts
/// (cleanupPeriodDays, 30 days by default).
///
/// A day is "sealed" once it's at least a full day old: its totals are
/// computed once from every transcript on disk and never touched again.
/// Days from `sealedUntil` on are always counted live from the transcripts,
/// so nothing is counted twice, not even across restarts.
final class UsageArchive {
    struct Day: Codable {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite5m = 0
        var cacheWrite1h = 0
        var cost: Double = 0

        init() {}

        init(_ t: Tokens) {
            input = t.input
            output = t.output
            cacheRead = t.cacheRead
            cacheWrite5m = t.cacheWrite5m
            cacheWrite1h = t.cacheWrite1h
            cost = t.cost
        }

        var tokens: Tokens {
            Tokens(input: input, output: output, cacheRead: cacheRead,
                   cacheWrite5m: cacheWrite5m, cacheWrite1h: cacheWrite1h, cost: cost)
        }
    }

    private struct Stored: Codable {
        var version = 1
        /// First day that is NOT sealed yet ("yyyy-MM-dd", local time).
        var sealedUntil: String?
        /// "yyyy-MM-dd" → totals of that day, across all models.
        var days: [String: Day] = [:]
    }

    /// What the scan needs, read in one go so the pair stays consistent.
    struct Summary {
        var total = Tokens()
        var sealedUntil: Date?
        var firstDay: Date?
    }

    let url: URL
    private var stored = Stored()
    private let lock = NSLock()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(url: URL = HookPaths.directory.appendingPathComponent("usage-archive.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
    }

    var summary: Summary {
        lock.lock()
        defer { lock.unlock() }
        var result = Summary()
        for day in stored.days.values { result.total += day.tokens }
        result.sealedUntil = stored.sealedUntil.flatMap(Self.dayFormatter.date(from:))
        result.firstDay = stored.days.keys.min().flatMap(Self.dayFormatter.date(from:))
        return result
    }

    var sealedUntil: Date? {
        lock.lock()
        defer { lock.unlock() }
        return stored.sealedUntil.flatMap(Self.dayFormatter.date(from:))
    }

    /// Stores the totals of days in [old sealedUntil, `until`) and moves the
    /// boundary to `until`. Days already sealed are left alone.
    func seal(_ days: [Date: Tokens], until: Date) {
        lock.lock()
        let boundary = stored.sealedUntil.flatMap(Self.dayFormatter.date(from:)) ?? .distantPast
        for (day, tokens) in days where day >= boundary && day < until && tokens.total > 0 {
            stored.days[Self.dayFormatter.string(from: day)] = Day(tokens)
        }
        stored.sealedUntil = Self.dayFormatter.string(from: until)
        let snapshot = stored
        lock.unlock()
        save(snapshot)
    }

    private func save(_ snapshot: Stored) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
