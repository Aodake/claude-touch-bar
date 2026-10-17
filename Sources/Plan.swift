import Foundation

/// How far Claude is through its task list, for the progress bar.
struct PlanProgress {
    let done: Int
    let total: Int
    let current: String?
    /// Estimated time left, from the average time per finished step.
    let eta: TimeInterval?

    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// The task list of one session, rebuilt from the hooks of the tools Claude
/// keeps it with: `mcp__ccd_turn__update_plan` in the desktop app, `TodoWrite`
/// in the CLI.
final class PlanState {
    private var items: [(content: String, status: String)] = []
    private var started = Date()
    private var lastCompletion: Date?
    private var completions = 0

    static let tools: Set<String> = ["mcp__ccd_turn__update_plan", "TodoWrite"]

    func apply(_ input: [String: Any]) {
        let before = doneCount
        if let list = (input["items"] ?? input["todos"]) as? [[String: Any]] {
            let newItems = list.map { ($0["content"] as? String ?? "", $0["status"] as? String ?? "pending") }
            // A fresh list, or a new one after the old one finished, restarts the clock.
            let newDone = newItems.filter { $0.1 == "completed" }.count
            let restart = items.isEmpty || before == items.count || newDone < before
            items = newItems
            if restart {
                // Steps already ticked off in a fresh list carry no timing.
                started = Date()
                completions = 0
                lastCompletion = nil
            } else if newDone > before {
                completions += newDone - before
                lastCompletion = Date()
            }
            return
        }
        if input["advance"] as? Bool == true, let index = items.firstIndex(where: { $0.status == "in_progress" }) {
            items[index].status = "completed"
            if let next = items.indices.first(where: { $0 > index && items[$0].status == "pending" }) {
                items[next].status = "in_progress"
            }
        }
        for number in input["done"] as? [Int] ?? [] where items.indices.contains(number - 1) {
            items[number - 1].status = "completed"
        }
        if let number = input["start"] as? Int, items.indices.contains(number - 1) {
            for i in items.indices where items[i].status == "in_progress" { items[i].status = "pending" }
            items[number - 1].status = "in_progress"
        }
        let finished = doneCount - before
        if finished > 0 {
            completions += finished
            lastCompletion = Date()
        }
    }

    private var doneCount: Int { items.filter { $0.status == "completed" }.count }

    /// nil when there's no list, or a finished one went stale.
    var progress: PlanProgress? {
        guard !items.isEmpty else { return nil }
        let done = doneCount
        if done == items.count, let last = lastCompletion, Date().timeIntervalSince(last) > 120 { return nil }
        var eta: TimeInterval?
        if completions > 0, let last = lastCompletion, done < items.count {
            let perStep = last.timeIntervalSince(started) / Double(completions)
            eta = max(0, perStep * Double(items.count - done) - Date().timeIntervalSince(last))
        }
        let current = items.first { $0.status == "in_progress" }?.content
        return PlanProgress(done: done, total: items.count, current: current, eta: eta)
    }
}
