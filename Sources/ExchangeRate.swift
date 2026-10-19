import Foundation

/// The USD/CZK rate for showing costs in Kč. Downloaded once in a while from
/// the Czech National Bank's public daily fixing (no user data is sent) and
/// only while the UI is Czech and "Show Kč" is on.
enum ExchangeRate {
    private static let defaults = UserDefaults.standard
    private static let url = URL(string: "https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/denni_kurz.txt")!
    /// Used until the first successful download.
    static let fallback = 21.7
    /// ČNB publishes once per working day; checking every few hours is plenty.
    private static let interval: TimeInterval = 6 * 3600
    private static var inFlight = false

    /// CZK for one USD.
    static var usdCZK: Double {
        let saved = defaults.double(forKey: "usdCZK")
        return saved > 0 ? saved : fallback
    }

    /// The ČNB fixing date of the saved rate ("19.10.2026"); nil while on the fallback.
    static var date: String? { defaults.string(forKey: "usdCZKDate") }

    /// Downloads a fresh rate when Kč is shown and the last try is old enough.
    /// `wait` blocks until done (for `--dump`, which exits right after).
    static func refreshIfNeeded(wait: Bool = false) {
        guard Settings.showsCZK, !inFlight else { return }
        let lastTry = defaults.object(forKey: "usdCZKTried") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastTry) > interval else { return }
        inFlight = true
        defaults.set(Date(), forKey: "usdCZKTried")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            // On failure the saved (or fallback) rate stays.
            if let parsed = data.flatMap({ String(data: $0, encoding: .utf8) }).flatMap(parse) {
                defaults.set(parsed.rate, forKey: "usdCZK")
                defaults.set(parsed.date, forKey: "usdCZKDate")
            }
            inFlight = false
            done.signal()
        }.resume()
        if wait { done.wait() }
    }

    /// "19.10.2026 #201" header, then "USA|dolar|1|USD|21,690".
    static func parse(_ text: String) -> (rate: Double, date: String)? {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let header = lines.first,
              let date = header.split(separator: " ").first,
              let line = lines.first(where: { $0.split(separator: "|").dropFirst(3).first == "USD" })
        else { return nil }
        let fields = line.split(separator: "|")
        guard fields.count == 5,
              let amount = Double(fields[2]),
              let rate = Double(fields[4].replacingOccurrences(of: ",", with: ".")),
              amount > 0, rate > 0
        else { return nil }
        return (rate / amount, String(date))
    }
}
