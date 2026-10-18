import AppKit

/// Owns the Control Strip icon and the Claude bar: three layouts, the
/// approval bar, and the ⋯ row with quick actions.
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let trayID = NSTouchBarItem.Identifier("local.ClaudeTouchBar.tray")

    private enum ID {
        static let state = NSTouchBarItem.Identifier("local.ClaudeTouchBar.state")
        static let context = NSTouchBarItem.Identifier("local.ClaudeTouchBar.context")
        static let tokens = NSTouchBarItem.Identifier("local.ClaudeTouchBar.tokens")
        static let cost = NSTouchBarItem.Identifier("local.ClaudeTouchBar.cost")
        static let graph = NSTouchBarItem.Identifier("local.ClaudeTouchBar.graph")
        static let model = NSTouchBarItem.Identifier("local.ClaudeTouchBar.model")
        static let session = NSTouchBarItem.Identifier("local.ClaudeTouchBar.session")
        static let fiveHours = NSTouchBarItem.Identifier("local.ClaudeTouchBar.fiveHours")
        static let today = NSTouchBarItem.Identifier("local.ClaudeTouchBar.today")
        static let wide = NSTouchBarItem.Identifier("local.ClaudeTouchBar.wide")
        static let switcher = NSTouchBarItem.Identifier("local.ClaudeTouchBar.switcher")
        static let more = NSTouchBarItem.Identifier("local.ClaudeTouchBar.more")
        static let back = NSTouchBarItem.Identifier("local.ClaudeTouchBar.back")
        static let approvalInfo = NSTouchBarItem.Identifier("local.ClaudeTouchBar.approvalInfo")
        static let allow = NSTouchBarItem.Identifier("local.ClaudeTouchBar.allow")
        static let always = NSTouchBarItem.Identifier("local.ClaudeTouchBar.always")
        static let deny = NSTouchBarItem.Identifier("local.ClaudeTouchBar.deny")
        static let stop = NSTouchBarItem.Identifier("local.ClaudeTouchBar.stop")
        static let new = NSTouchBarItem.Identifier("local.ClaudeTouchBar.new")
        static let sessions = NSTouchBarItem.Identifier("local.ClaudeTouchBar.sessions")
        static let detail = NSTouchBarItem.Identifier("local.ClaudeTouchBar.detail")
        static let push = NSTouchBarItem.Identifier("local.ClaudeTouchBar.push")
        static let cardInfo = NSTouchBarItem.Identifier("local.ClaudeTouchBar.cardInfo")
        static let cardButtons = (0..<3).map { NSTouchBarItem.Identifier("local.ClaudeTouchBar.card\($0)") }
        static let cardClose = NSTouchBarItem.Identifier("local.ClaudeTouchBar.cardClose")
        static let mode = NSTouchBarItem.Identifier("local.ClaudeTouchBar.mode")
        static let plan = NSTouchBarItem.Identifier("local.ClaudeTouchBar.plan")
        static let collapse = NSTouchBarItem.Identifier("local.ClaudeTouchBar.collapse")
        static let modeOptions = ClaudeUI.touchBarModes.indices.map {
            NSTouchBarItem.Identifier("local.ClaudeTouchBar.modeOption\($0)")
        }
        static let week = item(.week), month = item(.month), rate = item(.rate), active = item(.active)
        static let files = item(.files), waiting = item(.waiting), compact = item(.compact)
        static let modelPicker = item(.modelPicker)
        static let effort = NSTouchBarItem.Identifier("local.ClaudeTouchBar.effort")
        static let modelOptions = ClaudeUI.touchBarModels.indices.map {
            NSTouchBarItem.Identifier("local.ClaudeTouchBar.modelOption\($0)")
        }

        static func item(_ item: BarItem) -> NSTouchBarItem.Identifier {
            NSTouchBarItem.Identifier("local.ClaudeTouchBar.\(item.rawValue)")
        }
    }

    private static let spinnerFrames = ["✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳"]

    var onOpenDetail: (() -> Void)?
    var onTrayTap: (() -> Void)?
    var onLayoutChange: ((Layout) -> Void)?
    var onApproval: ((UUID, ApprovalDecision) -> Void)?
    var onCycleSession: (() -> Void)?
    var onCardButton: ((String) -> Void)?
    var onCardDismiss: (() -> Void)?
    var onSetMode: ((String) -> Void)?
    /// ⤓ was tapped: the Mac's own Touch Bar is back until ✳ is tapped.
    var onCollapse: (() -> Void)?
    var onSetModel: ((String) -> Void)?
    var onCycleEffort: (() -> Void)?
    var onOpenWaiting: (() -> Void)?
    /// The mode row (Manual / Auto / Accept edits / Plan), opened from ⋯.
    private var showingModes = false
    /// The model row (Opus / Fable / Sonnet / Haiku + effort).
    private var showingModels = false

    /// In Claude the bar takes the whole strip with your layout; elsewhere it
    /// pops up compact, next to brightness and volume.
    var claudeFrontmost = false {
        didSet {
            guard claudeFrontmost != oldValue else { return }
            applyIdentifiers()
            if isPresented { present() }
        }
    }

    private(set) var isPresented = false
    private var presentedFullWidth = false
    private(set) var layout = Settings.layout
    private let bar = NSTouchBar()
    /// The ⋯ actions row. A real NSPopoverTouchBarItem doesn't open on a
    /// system-modal bar, so ⋯ swaps the bar's items instead.
    private var showingActions = false
    /// Brief "✓ Allowed" after a tap, so the answer visibly landed.
    private var confirmation: (String, NSColor)?
    private var actionsTimeout: DispatchWorkItem?
    private var buttons: [NSTouchBarItem.Identifier: NSButton] = [:]
    private var trayItem: NSCustomTouchBarItem?
    private let trayButton = NSButton(title: "", target: nil, action: nil)
    private var snapshot = Snapshot()
    private var approvals: [ApprovalRequest] = []
    private var card: ClaudeUI.Card?
    private var animationTimer: Timer?
    private var tick = 0
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)

    /// Blinks the Control Strip icon until you look at Claude.
    var needsAttention = false {
        didSet { updateAnimation() }
    }

    override init() {
        super.init()
        bar.delegate = self

        let all = [ID.state, ID.context, ID.tokens, ID.cost, ID.graph, ID.model, ID.session, ID.fiveHours,
                   ID.today, ID.wide, ID.switcher, ID.more, ID.back, ID.approvalInfo, ID.allow, ID.always,
                   ID.deny, ID.stop, ID.new, ID.push, ID.sessions, ID.detail, ID.cardInfo, ID.cardClose]
                   + ID.cardButtons + [ID.mode, ID.plan, ID.collapse] + ID.modeOptions
                   + BarItem.allCases.map(ID.item) + [ID.effort] + ID.modelOptions
        for id in Set(all) {
            let button = NSButton(title: "", target: self, action: #selector(tapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            buttons[id] = button
        }

        localizeLabels()
        buttons[ID.switcher]?.widthAnchor.constraint(equalToConstant: 44).isActive = true
        buttons[ID.graph]?.imagePosition = .imageOnly
        configure(ID.sessions, symbol: "rectangle.stack", label: nil)
        // Push shows the git state next to its icon, so it isn't icon-only.
        configure(ID.push, symbol: "arrow.up.circle", label: nil)
        configure(ID.mode, symbol: "shield.lefthalf.filled", label: nil)
        buttons[ID.collapse]?.widthAnchor.constraint(equalToConstant: 44).isActive = true
        buttons[ID.cardClose]?.widthAnchor.constraint(equalToConstant: 40).isActive = true
        buttons[ID.cardButtons[0]]?.bezelColor = Palette.claude.blended(withFraction: 0.35, of: .black)
        for id in [ID.stop, ID.new, ID.detail] {
            buttons[id]?.widthAnchor.constraint(equalToConstant: 48).isActive = true
        }
        buttons[ID.more]?.widthAnchor.constraint(equalToConstant: 44).isActive = true
        configure(ID.back, symbol: "chevron.left", label: nil)
        configure(ID.modelPicker, symbol: "cpu", label: nil)
        configure(ID.files, symbol: "pencil", label: nil)
        configure(ID.compact, symbol: "arrow.down.right.and.arrow.up.left", label: nil)
        buttons[ID.compact]?.bezelColor = Palette.warning.blended(withFraction: 0.45, of: .black)
        for (index, model) in ClaudeUI.touchBarModels.enumerated() {
            set(ID.modelOptions[index], [(model, .white)])
        }
        buttons[ID.always]?.bezelColor = NSColor(srgbRed: 0.16, green: 0.36, blue: 0.62, alpha: 1)

        applyIdentifiers()
    }

    /// Fixed titles and icon descriptions in the current UI language.
    private func localizeLabels() {
        configure(ID.switcher, symbol: "rectangle.3.group", label: L("Přepnout rozložení", "Switch layout"))
        configure(ID.graph, symbol: nil, label: L("Spotřeba za poslední hodinu", "Spend in the last hour"))
        // Icon-only so the ⋯ row also fits Allow / Deny.
        configure(ID.stop, symbol: "stop.fill", label: L("Zastavit", "Stop"))
        configure(ID.new, symbol: "plus", label: L("Nové sezení", "New session"))
        configure(ID.detail, symbol: "info.circle", label: "Detail")
        configure(ID.collapse, symbol: "chevron.down.circle", label: L("Zmenšit na Touch Bar Macu", "Shrink to the Mac's Touch Bar"))
        configure(ID.cardClose, symbol: "xmark", label: L("Zavřít kartu", "Close card"))
        configure(ID.more, symbol: "ellipsis.circle", label: L("Akce", "Actions"))
        set(ID.back, [(L(" Zpět", " Back"), .white)])
        set(ID.compact, [(L(" Zkomprimovat", " Compact"), .white)])
        set(ID.effort, [(L("Úsilí ▸", "Effort ▸"), .white)])
        set(ID.always, [(L("Vždy povolit", "Always allow"), .white)])
    }

    /// The UI language changed: retitle everything and rebuild the bar.
    func languageChanged() {
        localizeLabels()
        applyIdentifiers()
        if isPresented { present() }
    }

    private func configure(_ id: NSTouchBarItem.Identifier, symbol: String?, label: String?) {
        guard let button = buttons[id] else { return }
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) }
        if label != nil && symbol != nil { button.imagePosition = .imageOnly }
    }

    // MARK: - Control Strip icon

    func installTrayIcon() {
        trayButton.target = self
        trayButton.action = #selector(trayTapped)
        trayButton.imagePosition = .imageOnly
        trayButton.image = Spark.image(size: 20, color: Palette.claude)
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        item.view = trayButton
        trayItem = item
        SystemTouchBar.addToControlStrip(item)
    }

    func removeTrayIcon() {
        if let trayItem { SystemTouchBar.removeFromControlStrip(trayItem) }
    }

    @objc private func trayTapped() {
        needsAttention = false
        present()
        onTrayTap?()
    }

    // MARK: - Showing and hiding

    func present() {
        let fullWidth = Settings.fullWidth && claudeFrontmost
        // Presenting again keeps the old placement, so switching between
        // compact and full width needs the bar taken down first.
        if isPresented && presentedFullWidth != fullWidth { SystemTouchBar.dismiss(bar) }
        SystemTouchBar.present(bar, trayIdentifier: Self.trayID, fullWidth: fullWidth)
        presentedFullWidth = fullWidth
        isPresented = true
    }

    func minimize() {
        guard isPresented else { return }
        SystemTouchBar.minimize(bar)
        isPresented = false
        ensureTrayIcon()
    }

    /// The full-width bar can knock ✳ out of the Control Strip; put it back
    /// so there's always a way back to the Claude bar.
    /// The Touch Bar server swaps bars asynchronously and drops an icon added
    /// mid-swap, so add it again a moment later too.
    func ensureTrayIcon() {
        guard let trayItem else { return }
        SystemTouchBar.addToControlStrip(trayItem)
        for delay in [0.4, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.isPresented || !self.presentedFullWidth else { return }
                SystemTouchBar.addToControlStrip(trayItem)
            }
        }
    }

    /// ⌃⌥C: show the Claude bar, or put it away if it's showing.
    func toggle() {
        if isPresented {
            minimize()
        } else {
            needsAttention = false
            present()
            onTrayTap?()
        }
    }

    func setLayout(_ newLayout: Layout) {
        layout = newLayout
        Settings.layout = newLayout
        applyIdentifiers()
        if isPresented { present() }
        onLayoutChange?(newLayout)
    }

    func setCard(_ newCard: ClaudeUI.Card?) {
        card = newCard
        if newCard != nil { showingActions = false }
        applyIdentifiers()
        if isPresented { present() }
    }

    func setApprovals(_ list: [ApprovalRequest]) {
        let changed = list.map(\.id) != approvals.map(\.id)
        approvals = list
        guard changed else { return }
        applyIdentifiers()
        if isPresented { present() }
    }

    private func applyIdentifiers() {
        if let (text, color) = confirmation {
            set(ID.approvalInfo, [(text, color)])
            bar.defaultItemIdentifiers = [ID.approvalInfo]
            return
        }
        if let first = approvals.first {
            bar.defaultItemIdentifiers = first.canAlwaysAllow
                ? [ID.approvalInfo, ID.allow, ID.always, ID.deny]
                : [ID.approvalInfo, ID.allow, ID.deny]
        } else if let card {
            bar.defaultItemIdentifiers = [ID.cardInfo] + ID.cardButtons.prefix(card.buttons.count) + [ID.cardClose]
        } else if showingModes {
            bar.defaultItemIdentifiers = [ID.back] + ID.modeOptions
        } else if showingModels {
            bar.defaultItemIdentifiers = [ID.back] + ID.modelOptions + [ID.effort]
        } else if showingActions {
            bar.defaultItemIdentifiers = [ID.back, ID.allow, ID.deny, ID.stop, ID.new, ID.push, ID.mode,
                                          ID.modelPicker, ID.sessions, ID.detail]
        } else {
            bar.defaultItemIdentifiers = layoutIdentifiers()
        }
        render()
    }

    /// Your chosen items for the layout, minus those with nothing to show
    /// right now. Outside Claude it's always the compact layout.
    private func layoutIdentifiers() -> [NSTouchBarItem.Identifier] {
        let current = claudeFrontmost ? layout : .compact
        let s = snapshot
        return LayoutItems.items(current).filter { item in
            switch item {
            case .plan: return s.plan != nil
            case .push: return s.git != nil
            case .compact: return s.contextFraction >= 0.8
            case .waiting: return s.waitingCount > 0
            case .files: return !s.changedFiles.isEmpty
            case .collapse: return claudeFrontmost && Settings.fullWidth
            default: return true
            }
        }.map(ID.item)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let button = buttons[identifier] else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = button
        switch identifier {
        case ID.graph, ID.model, ID.fiveHours, ID.sessions:
            item.visibilityPriority = .low
        case ID.switcher, ID.more, ID.state, ID.wide, ID.allow, ID.deny:
            item.visibilityPriority = .high
        default:
            break
        }
        return item
    }

    @objc private func tapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue else { return }
        let id = NSTouchBarItem.Identifier(raw)
        let approval = approvals.first
        switch id {
        case ID.switcher: setLayout(layout.next)
        case ID.state, ID.approvalInfo, ID.cardInfo: ClaudeApp.activate()
        case ID.cardClose: onCardDismiss?()
        case ID.mode:
            showingModes = true
            setShowingActions(true)
            applyIdentifiers()
            if isPresented { present() }
        case _ where ID.modeOptions.contains(id):
            if let index = ID.modeOptions.firstIndex(of: id) {
                setShowingActions(false)
                onSetMode?(ClaudeUI.touchBarModes[index])
            }
        case _ where ID.cardButtons.contains(id):
            if let card, let index = ID.cardButtons.firstIndex(of: id), index < card.buttons.count {
                onCardButton?(card.buttons[index])
            }
        case ID.allow, ID.always, ID.deny:
            let decision: ApprovalDecision = id == ID.allow ? .allow : id == ID.always ? .always : .deny
            if let approval {
                answer(approval, decision)
            } else {
                flash(L("Nic nečeká na schválení", "Nothing waits for approval"), Palette.dim)
            }
        case ID.more: setShowingActions(true)
        case ID.modelPicker:
            showingModels = true
            setShowingActions(true)
            applyIdentifiers()
            if isPresented { present() }
        case _ where ID.modelOptions.contains(id):
            if let index = ID.modelOptions.firstIndex(of: id) {
                setShowingActions(false)
                onSetModel?(ClaudeUI.touchBarModels[index])
            }
        case ID.effort:
            // Stay on the row: each tap moves effort one level, like in the app.
            setShowingActions(true)
            onCycleEffort?()
        case ID.waiting: onOpenWaiting?()
        case ID.compact:
            if KeySender.sendMessage("/compact") {
                flash(L("⇣ Posláno: /compact", "⇣ Sent: /compact"), Palette.claude)
            } else {
                flash(L("Povol aplikaci Zpřístupnění v Nastavení systému", "Allow the app in System Settings → Accessibility"), Palette.warning)
            }
        case ID.collapse:
            minimize()
            onCollapse?()
        case ID.back: setShowingActions(false)
        case ID.stop:
            setShowingActions(false)
            KeySender.send(KeySender.escape)
        case ID.new:
            setShowingActions(false)
            KeySender.send(KeySender.n, flags: .maskCommand)
        case ID.sessions:
            // Stay on the actions row so you can keep cycling.
            setShowingActions(true)
            onCycleSession?()
        case ID.push:
            // Claude writes the commit message and pushes in the open chat.
            if KeySender.sendMessage(L("Commitni a pushni změny", "Commit and push the changes")) {
                flash(L("↑ Posláno Claudovi: commit a push", "↑ Sent to Claude: commit and push"), Palette.claude)
            } else {
                flash(L("Povol aplikaci Zpřístupnění v Nastavení systému", "Allow the app in System Settings → Accessibility"), Palette.warning)
            }
        case ID.detail:
            setShowingActions(false)
            onOpenDetail?()
        default:
            onOpenDetail?()
        }
    }

    private func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) {
        onApproval?(request.id, decision)
        switch decision {
        case .allow: flash(L("✓ Povoleno · ", "✓ Allowed · ") + request.toolName, Palette.done)
        case .always: flash(L("✓ Vždy povoleno · ", "✓ Always allowed · ") + request.toolName, Palette.done)
        case .deny: flash(L("✕ Zamítnuto · ", "✕ Denied · ") + request.toolName, Palette.danger)
        }
    }

    /// After an effort tap: show the new level on its button, keep the row open.
    func setEffortLabel(_ label: String) {
        set(ID.effort, [(L("Úsilí: ", "Effort: ") + label + " ▸", .white)])
    }

    /// Shows a one-line message for 1.5 s, then the normal bar again.
    func flash(_ text: String, _ color: NSColor) {
        showingActions = false
        showingModes = false
        showingModels = false
        actionsTimeout?.cancel()
        confirmation = (text, color)
        applyIdentifiers()
        if isPresented { present() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.confirmation = nil
            self.applyIdentifiers()
            if self.isPresented { self.present() }
        }
    }

    /// Shows the ⋯ row; it falls back to the normal bar after 15 s untouched.
    func setShowingActions(_ show: Bool) {
        actionsTimeout?.cancel()
        if show {
            let work = DispatchWorkItem { [weak self] in self?.setShowingActions(false) }
            actionsTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        }
        let closingModes = !show && (showingModes || showingModels)
        if !show {
            showingModes = false
            showingModels = false
        }
        guard show != showingActions || closingModes else { return }
        showingActions = show
        applyIdentifiers()
        if isPresented { present() }
    }

    // MARK: - Animation

    func update(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        updateAnimation()
        // Items that come and go (plan, push, compact…) need the bar rebuilt.
        let normalBar = confirmation == nil && approvals.isEmpty && card == nil
            && !showingActions && !showingModes && !showingModels
        if normalBar && layoutIdentifiers() != bar.defaultItemIdentifiers {
            applyIdentifiers()
            if isPresented { present() }
        } else {
            render()
        }
    }

    private var isAnimating: Bool {
        snapshot.activity == .working || snapshot.activity == .waiting || needsAttention
    }

    private func updateAnimation() {
        if isAnimating, animationTimer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.animate() }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !isAnimating {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        drawSparks()
    }

    private func animate() {
        tick += 1
        drawSparks()
        // Text-based items (timers, spinner glyphs) only need ~3 updates a second.
        if tick % 3 == 0 { render() }
    }

    private var stateColor: NSColor {
        switch snapshot.activity {
        case .working, .idle: return Palette.claude
        case .waiting: return Palette.waiting
        case .done: return Palette.done
        }
    }

    private func stateImage(size: CGFloat) -> NSImage {
        let t = CGFloat(tick) * 0.05
        switch snapshot.activity {
        case .working:
            return Spark.image(size: size, color: Palette.claude, phase: t * 1.4, scale: 0.86 + 0.14 * sin(t * 5))
        case .waiting:
            return Spark.image(size: size, color: Palette.waiting.withAlphaComponent(0.55 + 0.45 * abs(sin(t * 3))))
        case .done:
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.8, weight: .semibold)
                .applying(.init(paletteColors: [Palette.done]))
            return NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: L("Hotovo", "Done"))?
                .withSymbolConfiguration(config) ?? Spark.image(size: size, color: Palette.done)
        case .idle:
            return Spark.image(size: size, color: Palette.claude)
        }
    }

    private func drawSparks() {
        buttons[ID.state]?.image = stateImage(size: 18)
        var tray = stateImage(size: 20)
        if needsAttention && (tick / 10) % 2 == 1 {
            tray = Spark.image(size: 20, color: Palette.dim)
        }
        trayButton.image = tray
    }

    // MARK: - Rendering

    private var glyph: (String, NSColor) {
        switch snapshot.activity {
        case .working: return (Self.spinnerFrames[(tick / 3) % Self.spinnerFrames.count], Palette.claude)
        case .waiting: return ("●", Palette.waiting)
        case .done: return ("✓", Palette.done)
        case .idle: return ("✳", Palette.claude)
        }
    }

    /// Running time of the current turn, or how long the last one took.
    private var turnTime: String? {
        guard let start = snapshot.turnStart else { return nil }
        switch snapshot.activity {
        case .working, .waiting:
            return Format.duration(Date().timeIntervalSince(start))
        case .done:
            guard let end = snapshot.turnEnd, end >= start else { return nil }
            return Format.duration(end.timeIntervalSince(start))
        case .idle:
            return nil
        }
    }

    private var stateWord: String {
        switch snapshot.activity {
        case .working: return L("Pracuje", "Working")
        case .waiting: return L("Čeká", "Waiting")
        case .done: return L("Hotovo", "Done")
        case .idle: return snapshot.hasSession ? L("Nečinný", "Idle") : L("Žádné sezení", "No session")
        }
    }

    /// "2/3" when more than one session is around.
    private var sessionPosition: String? {
        guard snapshot.sessions.count > 1 else { return nil }
        let index = snapshot.sessions.firstIndex { $0.url == snapshot.sessionURL }.map { $0 + 1 } ?? 1
        return "\(index)/\(snapshot.sessions.count)"
    }

    private var budgetFraction: Double? {
        let budget = Settings.dailyBudget
        return budget > 0 ? snapshot.today.cost / budget : nil
    }

    private func render() {
        let s = snapshot
        let ctxColor = Palette.context(s.contextFraction)
        let ctxText = Format.tokens(s.contextUsed)

        // State: smooth spark image, then time (or what it's waiting for).
        var stateParts: [(String, NSColor)] = [
            (" " + (s.activity == .waiting ? stateWord : (turnTime ?? stateWord)), .white),
        ]
        if let position = sessionPosition { stateParts.append(("  " + position, Palette.dim)) }
        set(ID.state, stateParts)

        // The overview has no state item, so its context item carries the glyph.
        let showGlyph = claudeFrontmost && layout == .overview
        buttons[ID.context]?.image = progressImage(s.contextFraction, width: showGlyph ? 44 : 56, color: ctxColor)
        if showGlyph {
            buttons[ID.context]?.imagePosition = .imageTrailing
            set(ID.context, [glyph, (" " + Format.percent(s.contextFraction) + " ", ctxColor)])
        } else {
            buttons[ID.context]?.imagePosition = .imageLeading
            set(ID.context, [(ctxText, ctxColor)])
        }

        set(ID.tokens, [("▲", Palette.dim), (Format.tokens(s.session.totalIn) + " ", .white),
                        ("▼", Palette.dim), (Format.tokens(s.session.output), .white)])
        set(ID.cost, [(Format.cost(s.session.cost), budgetColor)])
        set(ID.model, [(s.modelName, Palette.dim)])
        buttons[ID.graph]?.image = sparkline(s.burn, size: NSSize(width: 64, height: 20))

        set(ID.session, summary(L("Sezení", "Session"), s.session))
        set(ID.fiveHours, summary("5 h", s.fiveHours))
        if let fraction = budgetFraction {
            buttons[ID.today]?.image = progressImage(fraction, width: 36, color: budgetColor)
            buttons[ID.today]?.imagePosition = .imageTrailing
            set(ID.today, [(L("Dnes ", "Today "), Palette.dim), (Format.cost(s.today.cost), budgetColor),
                           ("/" + Format.cost(Settings.dailyBudget)
                            + (s.budgetRunway(Settings.dailyBudget).map { " " + Format.runway($0) } ?? "") + " ",
                            Palette.dim)])
        } else {
            buttons[ID.today]?.image = nil
            set(ID.today, summary(L("Dnes", "Today"), s.today))
        }

        buttons[ID.wide]?.image = progressImage(s.contextFraction, width: 140, color: ctxColor)
        if s.hasSession {
            var wide: [(String, NSColor)] = [
                (" \(ctxText) / \(Format.tokens(s.contextWindow))", ctxColor),
                ("  " + glyph.0 + " ", glyph.1),
                (turnTime ?? stateWord, .white),
            ]
            if let tool = s.tool { wide.append(("  " + truncate(tool, 14), Palette.dim)) }
            set(ID.wide, wide)
        } else {
            set(ID.wide, [(L(" Žádné Code sezení", " No Code session"), Palette.dim)])
        }

        let sessionLabel: String
        if s.isAutoSelected {
            sessionLabel = L(" Sezení: auto", " Session: auto") + (sessionPosition.map { " (\($0))" } ?? "")
        } else {
            sessionLabel = " " + (sessionPosition ?? "") + " " + truncate(s.title ?? s.project ?? L("sezení", "session"), 12)
        }
        set(ID.sessions, [(sessionLabel, .white)])

        // Push: branch, uncommitted changes (●) and unpushed commits (↑).
        if let git = s.git {
            let name = Settings.pushName.isEmpty ? git.branch : Settings.pushName
            var parts: [(String, NSColor)] = [(" " + truncate(name, 16), .white)]
            if git.changes > 0 { parts.append((" ●\(git.changes)", Palette.warning)) }
            if git.ahead > 0 { parts.append((" ↑\(git.ahead)", Palette.claude)) }
            set(ID.push, parts)
        } else {
            set(ID.push, [(" Push", .white)])
        }

        set(ID.week, summary(L("Týden", "Week"), s.week))
        set(ID.month, summary(L("Měsíc", "Month"), s.month))
        set(ID.rate, [(Format.cost(s.hourlyRate), .white), ("/h", Palette.dim)])
        set(ID.active, [("⏱ ", Palette.dim), (Format.minutes(s.activeMinutes), .white)])
        set(ID.files, [(" \(s.changedFiles.count) ", .white), (s.changedFiles.count == 1 ? L("soubor", "file") : L("souborů", "files"), Palette.dim)])
        set(ID.waiting, [("● ", Palette.waiting), ("\(s.waitingCount) " + L("čeká", "waiting"), .white)])
        set(ID.modelPicker, [(" " + s.modelName, .white)])

        if let plan = s.plan {
            let color = plan.done == plan.total ? Palette.done : Palette.claude
            buttons[ID.plan]?.image = progressImage(plan.fraction, width: 44, color: color)
            var parts: [(String, NSColor)] = [(" \(plan.done)/\(plan.total)", .white)]
            if let eta = plan.eta { parts.append((" ~" + Format.duration(eta), Palette.dim)) }
            set(ID.plan, parts)
        }

        let mode = s.mode ?? L("Režim", "Mode")
        set(ID.mode, [(" " + mode, .white)])
        for (index, option) in ClaudeUI.touchBarModes.enumerated() {
            let current = option == s.mode
            buttons[ID.modeOptions[index]]?.bezelColor = current ? Palette.claude.blended(withFraction: 0.35, of: .black) : nil
            set(ID.modeOptions[index], [((current ? "● " : "") + option, .white)])
        }

        // Allow / Deny are always in the ⋯ row; colored only when
        // something is actually waiting.
        let pending = !approvals.isEmpty
        buttons[ID.allow]?.bezelColor = pending ? NSColor(srgbRed: 0.18, green: 0.5, blue: 0.27, alpha: 1) : nil
        buttons[ID.deny]?.bezelColor = pending ? NSColor(srgbRed: 0.62, green: 0.18, blue: 0.16, alpha: 1) : nil
        set(ID.allow, [(L("Povolit", "Allow"), pending ? .white : Palette.dim)])
        set(ID.deny, [(L("Zamítnout", "Deny"), pending ? .white : Palette.dim)])

        renderApproval()
        renderCard()
    }

    private func renderCard() {
        guard let card else { return }
        set(ID.cardInfo, [("◆ ", Palette.claude), (truncate(card.title, 34), .white)])
        for (index, label) in card.buttons.enumerated() {
            set(ID.cardButtons[index], [(truncate(label, 18), .white)])
        }
    }

    private func renderApproval() {
        guard let request = approvals.first else { return }
        var parts: [(String, NSColor)] = [("● ", Palette.waiting)]
        if approvals.count > 1 { parts.append(("1/\(approvals.count) ", Palette.dim)) }
        parts.append((request.toolName, .white))
        if !request.summary.isEmpty { parts.append(("  " + truncate(request.summary, 34), Palette.dim)) }
        set(ID.approvalInfo, parts)
    }

    private var budgetColor: NSColor {
        guard let fraction = budgetFraction else { return .white }
        if fraction >= 1 { return Palette.danger }
        if fraction >= 0.8 { return Palette.warning }
        return .white
    }

    private func summary(_ label: String, _ t: Tokens) -> [(String, NSColor)] {
        [(label + " ", Palette.dim), (Format.tokens(t.total), .white), (" " + Format.cost(t.cost), Palette.dim)]
    }

    private func truncate(_ text: String, _ length: Int) -> String {
        text.count > length ? String(text.prefix(length - 1)) + "…" : text
    }

    private func set(_ id: NSTouchBarItem.Identifier, _ parts: [(String, NSColor)]) {
        let result = NSMutableAttributedString()
        for (text, color) in parts {
            result.append(NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font]))
        }
        buttons[id]?.attributedTitle = result
    }

    private func progressImage(_ fraction: Double, width: CGFloat, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: width, height: 8), flipped: false) { rect in
            NSColor(white: 1, alpha: 0.2).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            if fraction > 0 {
                var filled = rect
                filled.size.width = max(rect.height, rect.width * CGFloat(min(1, fraction)))
                color.setFill()
                NSBezierPath(roundedRect: filled, xRadius: 4, yRadius: 4).fill()
            }
            return true
        }
    }

    /// Bars of estimated spend per 5 minutes, last hour, newest on the right.
    private func sparkline(_ values: [Double], size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard !values.isEmpty else { return true }
            let peak = max(values.max() ?? 0, 0.0001)
            let gap: CGFloat = 1.5
            let width = (rect.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
            for (i, value) in values.enumerated() {
                let x = CGFloat(i) * (width + gap)
                let height = value > 0 ? max(2, rect.height * CGFloat(value / peak)) : 1
                let color = value > 0 ? Palette.claude : NSColor(white: 1, alpha: 0.25)
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: width, height: height),
                             xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
    }
}
