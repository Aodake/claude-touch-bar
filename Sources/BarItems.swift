import Foundation

/// Everything that can sit on the Touch Bar. The raw value is also the item's
/// Touch Bar identifier suffix, so it must stay stable.
enum BarItem: String, CaseIterable, Identifiable {
    case state, plan, context, session, fiveHours, today, week, month
    case tokens, cost, rate, active, graph, model, files, waiting, compact
    case push, modelPicker, wide, switcher, more, collapse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .state: return L("Stav a čas", "State and time")
        case .plan: return L("Postup plánu", "Plan progress")
        case .context: return L("Kontext", "Context")
        case .session: return L("Útrata sezení", "Session spend")
        case .fiveHours: return L("Útrata 5 h", "5 h spend")
        case .today: return L("Útrata dnes", "Today's spend")
        case .week: return L("Útrata týden", "Week's spend")
        case .month: return L("Útrata měsíc", "Month's spend")
        case .tokens: return L("Tokeny ▲▼", "Tokens ▲▼")
        case .cost: return L("Cena sezení", "Session cost")
        case .rate: return L("Tempo $/h", "Rate $/h")
        case .active: return L("Aktivní čas dnes", "Active time today")
        case .graph: return L("Graf poslední hodiny", "Last hour graph")
        case .model: return L("Název modelu", "Model name")
        case .files: return L("Změněné soubory", "Changed files")
        case .waiting: return L("Čekající sezení", "Waiting sessions")
        case .compact: return L("Zkomprimovat kontext", "Compact context")
        case .push: return L("Commit a push", "Commit and push")
        case .modelPicker: return L("Přepínač modelu", "Model picker")
        case .wide: return L("Velký kontext (Minimal)", "Large context (Minimal)")
        case .switcher: return L("Přepnout rozložení ⇄", "Switch layout ⇄")
        case .more: return L("Akce ⋯", "Actions ⋯")
        case .collapse: return L("Zmenšit ⤓", "Shrink ⤓")
        }
    }

    /// When the item only shows up while it has something to say.
    var condition: String? {
        switch self {
        case .plan: return L("jen když má Claude plán", "only when Claude has a plan")
        case .push: return L("jen s repozitářem pro Push", "only with a Push repository")
        case .compact: return L("jen nad 80 % kontextu", "only above 80% context")
        case .waiting: return L("jen když něco čeká", "only when something waits")
        case .files: return L("jen když Claude něco změnil", "only when Claude changed something")
        case .collapse: return L("jen přes celou šířku", "only at full width")
        default: return nil
        }
    }
}

enum LayoutItems {
    static func defaults(_ layout: Layout) -> [BarItem] {
        switch layout {
        case .compact:
            return [.state, .plan, .context, .session, .today, .waiting, .compact, .graph, .model, .push,
                    .switcher, .more, .collapse]
        case .overview:
            return [.context, .plan, .session, .fiveHours, .today, .week, .waiting, .push, .switcher, .more, .collapse]
        case .minimal:
            return [.graph, .plan, .wide, .push, .switcher, .more, .collapse]
        }
    }

    private static func key(_ layout: Layout) -> String { "items.\(layout.rawValue)" }

    static func items(_ layout: Layout) -> [BarItem] {
        guard let saved = UserDefaults.standard.stringArray(forKey: key(layout)) else { return defaults(layout) }
        return saved.compactMap(BarItem.init(rawValue:))
    }

    static func set(_ items: [BarItem], for layout: Layout) {
        UserDefaults.standard.set(items.map(\.rawValue), forKey: key(layout))
    }

    static func reset(_ layout: Layout) {
        UserDefaults.standard.removeObject(forKey: key(layout))
    }
}
