import AppKit
import Charts
import SwiftUI

final class DetailModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var approvals: [ApprovalRequest] = []
    @Published var selectedSession: URL?
    @Published var layout = Settings.layout
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var hooksInstalled = HookInstaller.isInstalled
    @Published var accessibilityTrusted = KeySender.isTrusted
    @Published var hookError: String?
    @Published var section: Section = .overview

    enum Section: String, CaseIterable, Identifiable {
        case overview, touchBar, integration, git, general
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Přehled"
            case .touchBar: return "Touch Bar"
            case .integration: return "Napojení na Claude"
            case .git: return "Git a Push"
            case .general: return "Obecné"
            }
        }

        var symbol: String {
            switch self {
            case .overview: return "chart.bar"
            case .touchBar: return "rectangle.3.group"
            case .integration: return "link"
            case .git: return "arrow.up.circle"
            case .general: return "gearshape"
            }
        }
    }

    var onLayoutPicked: ((Layout) -> Void)?
    var onSelectSession: ((URL?) -> Void)?
    var onApproval: ((UUID, ApprovalDecision) -> Void)?
    var onSettingsChanged: (() -> Void)?

    func reloadStatus() {
        launchAtLogin = LaunchAtLogin.isEnabled
        hooksInstalled = HookInstaller.isInstalled
        accessibilityTrusted = KeySender.isTrusted
    }

    /// Settings changed from the window: refresh both the window and the bar.
    func changed() {
        objectWillChange.send()
        onSettingsChanged?()
    }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        NavigationSplitView {
            List(DetailModel.Section.allCases, selection: Binding(
                get: { model.section },
                set: { if let section = $0 { model.section = section } }
            )) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.section {
                    case .overview: OverviewSection(model: model)
                    case .touchBar: TouchBarSection(model: model)
                    case .integration: IntegrationSection(model: model)
                    case .git: GitSection(model: model)
                    case .general: GeneralSection(model: model)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(model.section.title)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

/// A thin progress bar used across the sections.
struct Meter: View {
    let fraction: Double
    let color: NSColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color(nsColor: color))
                    .frame(width: max(6, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

private func toggle(_ model: DetailModel, _ title: String, _ get: @escaping () -> Bool,
                    _ set: @escaping (Bool) -> Void) -> some View {
    Toggle(title, isOn: Binding(get: get, set: { set($0); model.changed() }))
}

// MARK: - Přehled

struct OverviewSection: View {
    @ObservedObject var model: DetailModel
    private var s: Snapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let request = model.approvals.first { approvalBox(request) }
            context
            if let plan = s.plan { planBox(plan) }
            sessionPicker
            Divider()
            tokenTable
            HStack(spacing: 24) {
                stat("Tempo", Format.cost(s.hourlyRate) + "/h")
                stat("Aktivní dnes", Format.minutes(s.activeMinutes))
                stat("Změněné soubory", "\(s.changedFiles.count)")
            }
            charts
            budget
            if !s.changedFiles.isEmpty { filesList }
            Text("Cena je orientační odhad podle API ceníku, předplatné Pro/Max se po tokenech neplatí.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stateText: String {
        switch s.activity {
        case .working: return "pracuje"
        case .waiting: return "čeká na tebe"
        case .done: return "hotovo"
        case .idle: return "nečinný"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.title ?? (s.hasSession ? "Code sezení" : "Žádné Code sezení")).font(.title3.bold())
            Text([s.project, s.hasSession ? s.modelName : nil, s.mode.map { "režim " + $0 }, stateText, s.tool]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
        }
    }

    private func approvalBox(_ request: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Čeká na schválení" + (model.approvals.count > 1 ? " (\(model.approvals.count))" : "")).bold()
            Text(request.toolName + (request.summary.isEmpty ? "" : ": " + request.summary))
                .font(.system(.body, design: .monospaced))
                .lineLimit(3)
            HStack {
                Button("Povolit") { model.onApproval?(request.id, .allow) }
                if request.canAlwaysAllow { Button("Vždy povolit") { model.onApproval?(request.id, .always) } }
                Button("Zamítnout", role: .destructive) { model.onApproval?(request.id, .deny) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Kontext")
                Spacer()
                Text("\(Format.tokens(s.contextUsed)) z \(Format.tokens(s.contextWindow)) · \(Format.percent(s.contextFraction))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Meter(fraction: s.contextFraction,
                  color: s.contextFraction >= 0.7 ? Palette.context(s.contextFraction) : Palette.claude)
        }
    }

    private func planBox(_ plan: PlanProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Postup")
                Spacer()
                Text("\(plan.done) z \(plan.total) kroků" + (plan.eta.map { " · zbývá ~" + Format.duration($0) } ?? ""))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Meter(fraction: plan.fraction, color: plan.done == plan.total ? Palette.done : Palette.claude)
            if let current = plan.current {
                Text("Teď: " + current).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var sessionPicker: some View {
        if s.sessions.count > 1 {
            Picker("Sezení", selection: Binding(get: { model.selectedSession }, set: { model.onSelectSession?($0) })) {
                Text("Automaticky (to, co tě potřebuje)").tag(URL?.none)
                ForEach(s.sessions) { session in
                    Text(session.title).tag(URL?.some(session.url))
                }
            }
        }
    }

    private var tokenTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 5) {
            GridRow {
                Text("").frame(maxWidth: .infinity).gridColumnAlignment(.leading)
                ForEach(["Sezení", "5 h", "Dnes", "Týden", "Měsíc"], id: \.self) { Text($0).bold() }
            }
            row("Vstup", \.input)
            row("Čtení z cache", \.cacheRead)
            row("Zápis do cache", \.cacheWrite)
            row("Výstup", \.output)
            Divider().gridCellUnsizedAxes(.horizontal)
            row("Celkem", \.total)
            GridRow {
                Text("Odhad ceny")
                ForEach(columns.indices, id: \.self) { Text(Format.cost(columns[$0].cost)) }
            }
            .bold()
        }
        .monospacedDigit()
    }

    private var columns: [Tokens] { [s.session, s.fiveHours, s.today, s.week, s.month] }

    private func row(_ label: String, _ key: KeyPath<Tokens, Int>) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            ForEach(columns.indices, id: \.self) { Text(Format.tokens(columns[$0][keyPath: key])) }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }

    private struct Bar: Identifiable {
        let date: Date
        let cost: Double
        var id: Date { date }
    }

    private var charts: some View {
        let now = Date()
        let hours = s.hourly.enumerated().map {
            Bar(date: now.addingTimeInterval(-Double(s.hourly.count - 1 - $0.offset) * 3600), cost: $0.element)
        }
        let today = Calendar.current.startOfDay(for: now)
        let days = s.daily.enumerated().map {
            Bar(date: Calendar.current.date(byAdding: .day, value: -(s.daily.count - 1 - $0.offset), to: today) ?? today,
                cost: $0.element)
        }
        return HStack(alignment: .top, spacing: 20) {
            chart("Posledních 24 h", hours, unit: .hour, stride: 6, format: .dateTime.hour())
            chart("Posledních 30 dní", days, unit: .day, stride: 7, format: .dateTime.day().month())
        }
    }

    private func chart(_ title: String, _ bars: [Bar], unit: Calendar.Component, stride: Int,
                       format: Date.FormatStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            Chart(bars) { bar in
                BarMark(x: .value("Čas", bar.date, unit: unit), y: .value("USD", bar.cost))
                    .foregroundStyle(Color(nsColor: Palette.claude))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: unit, count: stride)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: format)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(Format.cost(value.as(Double.self) ?? 0)) }
                }
            }
            .frame(height: 120)
        }
    }

    private var budget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Denní rozpočet")
                Spacer()
                TextField("vypnuto", value: Binding(
                    get: { Settings.dailyBudget > 0 ? Settings.dailyBudget : nil },
                    set: { Settings.dailyBudget = $0 ?? 0; model.changed() }
                ), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                Text("$")
            }
            if Settings.dailyBudget > 0 {
                let fraction = s.today.cost / Settings.dailyBudget
                Meter(fraction: fraction, color: fraction >= 1 ? Palette.danger : fraction >= 0.8 ? Palette.warning : Palette.claude)
                Text("Dnes \(Format.cost(s.today.cost)) z \(Format.cost(Settings.dailyBudget)) · \(Format.percent(fraction))"
                     + (s.budgetRunway(Settings.dailyBudget).map { " · při současném tempu vydrží \(Format.runway($0))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var filesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Změněné soubory v sezení").font(.subheadline)
            ForEach(s.changedFiles, id: \.self) { path in
                Text(path.replacingOccurrences(of: s.cwd.map { $0 + "/" } ?? "\u{0}", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - Touch Bar

struct TouchBarSection: View {
    @ObservedObject var model: DetailModel
    @State private var editing: Layout = Settings.layout
    @State private var items: [BarItem] = LayoutItems.items(Settings.layout)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vyber rozložení, zapni položky a přetažením je seřaď. Změny se na Touch Baru projeví hned. ⇄ na Touch Baru přepíná mezi rozloženími.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Rozložení", selection: $editing) {
                ForEach(Layout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: editing) { _, layout in items = LayoutItems.items(layout) }

            preview

            List {
                ForEach(items) { item in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Text(item.title)
                        if let condition = item.condition {
                            Text(condition).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            items.removeAll { $0 == item }
                            save()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Odebrat z Touch Baru")
                    }
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                    save()
                }
            }
            .frame(minHeight: 300)

            HStack {
                Menu("Přidat položku") {
                    ForEach(BarItem.allCases.filter { !items.contains($0) }) { item in
                        Button(item.title + (item.condition.map { " (\($0))" } ?? "")) {
                            items.append(item)
                            save()
                        }
                    }
                }
                .frame(width: 180)
                Spacer()
                Button("Obnovit výchozí") {
                    LayoutItems.reset(editing)
                    items = LayoutItems.items(editing)
                    model.changed()
                }
                Button("Použít na Touch Baru") {
                    model.layout = editing
                    model.onLayoutPicked?(editing)
                }
            }

            Divider()
            toggle(model, "Ukázat automaticky, když je Claude v popředí", { Settings.autoShow }, { Settings.autoShow = $0 })
            toggle(model, "V Claudovi přes celý Touch Bar (⤓ ho zmenší)", { Settings.fullWidth }, { Settings.fullWidth = $0 })
            Text("Mimo Claude se bar ukazuje kompaktně vedle jasu a hlasitosti, s položkami rozložení Kompaktní.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Rough look of the bar: the chosen items as capsules.
    private var preview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.25), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.white)
                }
            }
            .padding(6)
        }
        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
    }

    private func save() {
        LayoutItems.set(items, for: editing)
        model.changed()
    }
}

// MARK: - Napojení

struct IntegrationSection: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hooky Claude Code").bold()
                    Text(model.hooksInstalled
                         ? "Zapnuté: přesné stavy, aktuální nástroj, plán, schvalování a karty na Touch Baru (v nových sezeních)."
                         : "Vypnuté. Stav se odhaduje z přepisů; schvalování a karty nefungují.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(model.hooksInstalled ? "Vypnout" : "Zapnout") {
                    do {
                        if model.hooksInstalled { try HookInstaller.uninstall() } else { try HookInstaller.install() }
                        model.hookError = nil
                    } catch {
                        model.hookError = error.localizedDescription
                    }
                    model.reloadStatus()
                }
            }
            if let error = model.hookError { Text(error).font(.caption).foregroundStyle(.red) }

            Group {
                toggle(model, "Schvalovat z Touch Baru, když jsi mimo Claude", { Settings.approvals }, { Settings.approvals = $0 })
                toggle(model, "Schvalovat z Touch Baru i v aplikaci Claude", { Settings.approvalsInClaude }, { Settings.approvalsInClaude = $0 })
                toggle(model, "Ukazovat karty z Clauda (otázky, další krok, nová session)", { Settings.cards }, { Settings.cards = $0 })
                toggle(model, "Vyskočit, když Claude dokončí práci", { Settings.popOnDone }, { Settings.popOnDone = $0 })
                toggle(model, "Zvuk při dokončení a schvalování", { Settings.sound }, { Settings.sound = $0 })
            }
            .disabled(!model.hooksInstalled)

            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zpřístupnění").bold()
                    Text(model.accessibilityTrusted
                         ? "Povoleno: Zastavit, Nové, Push, režim, model a karty fungují."
                         : "Potřeba pro Zastavit, Nové, Push, režim, model a karty.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.accessibilityTrusted {
                    Button("Povolit") {
                        KeySender.requestTrust()
                        model.reloadStatus()
                    }
                }
            }
        }
    }
}

// MARK: - Git a Push

struct GitSection: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tlačítko ↑ ukazuje stav tohoto repozitáře a ťuknutím pošle do otevřeného chatu „Commitni a pushni změny“.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Název na Touch Baru") {
                TextField("Econs portal", text: Binding(
                    get: { Settings.pushName }, set: { Settings.pushName = $0; model.changed() }))
            }
            LabeledContent("Složka repozitáře") {
                HStack {
                    TextField("~/Documents/PortalEcons", text: Binding(
                        get: { Settings.pushRepo },
                        set: { Settings.pushRepo = ($0 as NSString).expandingTildeInPath; model.changed() }))
                    Button("Vybrat…") { chooseFolder() }
                }
            }
            if let git = model.snapshot.git {
                Text("Větev \(git.branch) · " + (git.changes == 0 ? "bez změn" : "\(git.changes) necommitnutých")
                     + (git.ahead > 0 ? " · \(git.ahead) k pushnutí" : ""))
                    .foregroundStyle(.secondary)
            } else if !Settings.pushRepo.isEmpty {
                Text("Ve složce není git repozitář, nebo se ještě načítá.").foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            Settings.pushRepo = url.path
            if Settings.pushName.isEmpty { Settings.pushName = url.lastPathComponent }
            model.changed()
        }
    }
}

// MARK: - Obecné

struct GeneralSection: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggle(model, "Spouštět po přihlášení", { model.launchAtLogin }, {
                LaunchAtLogin.setEnabled($0)
                model.launchAtLogin = LaunchAtLogin.isEnabled
            })
            Text("Okno otevřeš kdykoli znovu z Launchpadu nebo ťuknutím na číslo na Touch Baru. Po zavření okna aplikace dál běží na pozadí.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tokeny a ceny se čtou z přepisů Code tabu (~/.claude/projects). Chat tokeny lokálně neukládá.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Otevřít Claude") { ClaudeApp.activate() }
                Spacer()
                Button("Ukončit Claude Touch Bar") { NSApp.terminate(nil) }
            }
        }
    }
}

// MARK: - Controller

/// The app's window. While it's open the app shows in the Dock like any
/// other; closing it sends the app back to the background.
final class DetailWindowController: NSObject, NSWindowDelegate {
    let model = DetailModel()
    private var window: NSWindow?

    func show(section: DetailModel.Section? = nil) {
        if let section { model.section = section }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Claude Touch Bar"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.setFrameAutosaveName("ClaudeTouchBarWindow")
            if !window.setFrameUsingName("ClaudeTouchBarWindow") { window.center() }
            self.window = window
        }
        model.reloadStatus()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
