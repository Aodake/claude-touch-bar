import Foundation

/// API list prices in USD per million tokens. Only used for a rough estimate —
/// a Pro/Max subscription isn't billed per token.
struct ModelInfo {
    let shortName: String
    let input: Double
    let output: Double
    let cacheRead: Double
    let contextWindow: Int

    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2.0 }
}

enum Pricing {
    /// Most specific prefixes first.
    private static let table: [(prefix: String, info: ModelInfo)] = [
        ("claude-fable-5-1", ModelInfo(shortName: "fable 5.1", input: 10, output: 50, cacheRead: 0.25, contextWindow: 1_000_000)),
        ("claude-mythos-5-1", ModelInfo(shortName: "mythos 5.1", input: 10, output: 50, cacheRead: 0.25, contextWindow: 1_000_000)),
        ("claude-fable-5", ModelInfo(shortName: "fable 5", input: 10, output: 50, cacheRead: 1.0, contextWindow: 1_000_000)),
        ("claude-opus-5-5", ModelInfo(shortName: "opus 5.5", input: 4, output: 20, cacheRead: 0.20, contextWindow: 1_000_000)),
        ("claude-opus-5", ModelInfo(shortName: "opus 5", input: 5, output: 25, cacheRead: 0.50, contextWindow: 1_000_000)),
        ("claude-opus-4-8", ModelInfo(shortName: "opus 4.8", input: 5, output: 25, cacheRead: 0.50, contextWindow: 1_000_000)),
        ("claude-opus-4-7", ModelInfo(shortName: "opus 4.7", input: 5, output: 25, cacheRead: 0.50, contextWindow: 1_000_000)),
        ("claude-opus-4-6", ModelInfo(shortName: "opus 4.6", input: 5, output: 25, cacheRead: 0.50, contextWindow: 1_000_000)),
        ("claude-opus-4-5", ModelInfo(shortName: "opus 4.5", input: 5, output: 25, cacheRead: 0.50, contextWindow: 200_000)),
        ("claude-opus-4", ModelInfo(shortName: "opus 4", input: 15, output: 75, cacheRead: 1.50, contextWindow: 200_000)),
        ("claude-sonnet-5-5", ModelInfo(shortName: "sonnet 5.5", input: 2, output: 10, cacheRead: 0.20, contextWindow: 1_000_000)),
        ("claude-sonnet-5", ModelInfo(shortName: "sonnet 5", input: 2, output: 10, cacheRead: 0.20, contextWindow: 1_000_000)),
        ("claude-sonnet-4-6", ModelInfo(shortName: "sonnet 4.6", input: 3, output: 15, cacheRead: 0.30, contextWindow: 1_000_000)),
        ("claude-sonnet-4", ModelInfo(shortName: "sonnet 4", input: 3, output: 15, cacheRead: 0.30, contextWindow: 200_000)),
        ("claude-haiku-5-5", ModelInfo(shortName: "haiku 5.5", input: 0.10, output: 0.50, cacheRead: 0.01, contextWindow: 1_000_000)),
        ("claude-haiku-4-5", ModelInfo(shortName: "haiku 4.5", input: 1, output: 5, cacheRead: 0.10, contextWindow: 200_000)),
    ]

    private static let fallback = ModelInfo(shortName: "claude", input: 4, output: 20, cacheRead: 0.20, contextWindow: 1_000_000)

    static func info(for model: String?) -> ModelInfo {
        guard let model else { return fallback }
        return table.first { model.hasPrefix($0.prefix) }?.info ?? fallback
    }
}
