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
        case .state: return "Stav a čas"
        case .plan: return "Postup plánu"
        case .context: return "Kontext"
        case .session: return "Útrata sezení"
        case .fiveHours: return "Útrata 5 h"
        case .today: return "Útrata dnes"
        case .week: return "Útrata týden"
        case .month: return "Útrata měsíc"
        case .tokens: return "Tokeny ▲▼"
        case .cost: return "Cena sezení"
        case .rate: return "Tempo $/h"
        case .active: return "Aktivní čas dnes"
        case .graph: return "Graf poslední hodiny"
        case .model: return "Název modelu"
        case .files: return "Změněné soubory"
        case .waiting: return "Čekající sezení"
        case .compact: return "Zkomprimovat kontext"
        case .push: return "Commit a push"
        case .modelPicker: return "Přepínač modelu"
        case .wide: return "Velký kontext (Minimal)"
        case .switcher: return "Přepnout rozložení ⇄"
        case .more: return "Akce ⋯"
        case .collapse: return "Zmenšit ⤓"
        }
    }

    /// When the item only shows up while it has something to say.
    var condition: String? {
        switch self {
        case .plan: return "jen když má Claude plán"
        case .push: return "jen s repozitářem pro Push"
        case .compact: return "jen nad 80 % kontextu"
        case .waiting: return "jen když něco čeká"
        case .files: return "jen když Claude něco změnil"
        case .collapse: return "jen přes celou šířku"
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
