import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let touchBar = TouchBarController()
    private let detail = DetailWindowController()
    private let hooks = HookServer()
    private var refreshTimer: Timer?

    private var hookStates: [URL: HookState] = [:]
    /// nil = pick the session automatically.
    private var selectedSession: URL?
    private var lastSnapshot = Snapshot()
    private var previousActivity: [URL: Activity] = [:]
    private var warnedContext: Set<URL> = []
    private var approvalCount = 0
    private var card: ClaudeUI.Card?
    private var gitStatus: [String: GitStatus] = [:]
    private var plans: [URL: PlanState] = [:]
    private var gitTimer: Timer?

    private var claudeFrontmost = false
    /// True when the bar came up because Claude got focus, so it should also
    /// go away when Claude loses it. A bar opened from the Control Strip stays.
    private var autoPresented = false
    /// Pending auto-hide for a bar that popped up to tell you something.
    private var popHide: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }

        touchBar.onOpenDetail = { [weak self] in self?.detail.show() }
        touchBar.onTrayTap = { [weak self] in
            self?.autoPresented = false
            self?.popHide?.cancel()
        }
        touchBar.onLayoutChange = { [weak self] layout in self?.detail.model.layout = layout }
        touchBar.onApproval = { [weak self] id, decision in self?.hooks.answer(id, decision) }
        touchBar.onCycleSession = { [weak self] in self?.cycleSession() }
        touchBar.onCardButton = { [weak self] label in self?.pressCardButton(label) }
        touchBar.onCardDismiss = { [weak self] in self?.setCard(nil) }
        touchBar.onSetMode = { [weak self] mode in self?.setMode(mode) }
        touchBar.onSetModel = { [weak self] model in self?.setModel(model) }
        touchBar.onCycleEffort = { [weak self] in self?.cycleEffort() }
        touchBar.onOpenWaiting = { [weak self] in self?.openWaiting() }
        // ⤓ keeps the Mac's Touch Bar until you tap ✳ or come back to Claude.
        touchBar.onCollapse = { [weak self] in
            self?.autoPresented = false
            self?.popHide?.cancel()
        }
        let git = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refreshGit() }
        RunLoop.main.add(git, forMode: .common)
        gitTimer = git
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshGit() }

        let model = detail.model
        model.onLayoutPicked = { [weak self] layout in self?.touchBar.setLayout(layout) }
        model.onSelectSession = { [weak self] url in
            self?.selectedSession = url
            self?.refresh()
        }
        model.onApproval = { [weak self] id, decision in self?.hooks.answer(id, decision) }
        model.onSettingsChanged = { [weak self] in
            self?.updateHold()
            self?.refresh()
        }

        hooks.onEvent = { [weak self] event in self?.handleHook(event) }
        hooks.onApprovalsChanged = { [weak self] list in self?.approvalsChanged(list) }
        do {
            try hooks.start()
        } catch {
            NSLog("ClaudeTouchBar: hook socket unavailable: \(error)")
        }

        touchBar.installTrayIcon()
        installHotKey()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.hooks.pruneDisconnected()
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        if let front = NSWorkspace.shared.frontmostApplication { handleFrontmost(front) }
        updateHold()
        if CommandLine.arguments.contains("--show-actions") { touchBar.setShowingActions(true) }
        // Opened by hand (Launchpad, Finder): show the window. At login the
        // LaunchAgent passes --background and the app stays out of sight.
        if !CommandLine.arguments.contains("--background") { detail.show() }
    }

    /// ⌃⌥C anywhere shows or hides the Claude bar. Seeing other apps' keys
    /// needs the Accessibility permission the app already has.
    private var hotKeyMonitors: [Any] = []

    private func installHotKey() {
        let handler: (NSEvent) -> Bool = { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.control, .option], event.keyCode == 8 else { return false }  // 8 = C
            DispatchQueue.main.async {
                self?.autoPresented = false
                self?.popHide?.cancel()
                self?.touchBar.toggle()
            }
            return true
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = handler($0) }) {
            hotKeyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { handler($0) ? nil : $0 }) {
            hotKeyMonitors.append(local)
        }
    }

    /// Opening the app again while it runs brings up its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        detail.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hooks.stop()
        touchBar.minimize()
        touchBar.removeTrayIcon()
    }

    // MARK: - Data

    private func refresh() {
        store.refresh(selected: selectedSession, hooks: hookStates) { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    private func apply(_ incoming: Snapshot) {
        var snapshot = incoming
        snapshot.approval = hooks.approvals.first
        if let folder = gitFolder(for: snapshot) { snapshot.git = gitStatus[folder] }
        if let url = snapshot.sessionURL { snapshot.plan = plans[url]?.progress }
        // The pinned session disappeared: back to automatic.
        if selectedSession != nil && snapshot.isAutoSelected { selectedSession = nil }
        lastSnapshot = snapshot
        touchBar.update(snapshot)
        detail.model.snapshot = snapshot
        detail.model.selectedSession = selectedSession
        notifyTransitions(snapshot)
    }

    private func cycleSession() {
        let urls = lastSnapshot.sessions.map(\.url)
        guard !urls.isEmpty else { return }
        if let current = selectedSession, let index = urls.firstIndex(of: current) {
            selectedSession = index + 1 < urls.count ? urls[index + 1] : nil
        } else {
            selectedSession = urls[0]
        }
        refresh()
        // Also open it in Claude, so the bar and the window show the same chat.
        if let url = selectedSession, let title = lastSnapshot.sessions.first(where: { $0.url == url })?.title {
            openInClaude(title)
        }
    }

    private func openInClaude(_ title: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let opened = ClaudeUI.openSession(titled: title)
            DispatchQueue.main.async {
                if !opened { self?.touchBar.flash("Sezení „\(title)“ v postranním panelu nevidím", Palette.warning) }
            }
        }
    }

    /// The repository chosen for Push, or else the shown session's folder.
    private func gitFolder(for snapshot: Snapshot) -> String? {
        Settings.pushRepo.isEmpty ? snapshot.cwd : Settings.pushRepo
    }

    /// `git status` of the Push repository, refreshed every 10 s.
    private func refreshGit() {
        guard let cwd = gitFolder(for: lastSnapshot) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = Git.status(at: cwd)
            DispatchQueue.main.async {
                self?.gitStatus[cwd] = status
            }
        }
    }

    private func setModel(_ model: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let done = ClaudeUI.choose(model, in: "Model:")
            DispatchQueue.main.async {
                self?.touchBar.flash(done ? "✓ Model: " + model : "Výběr modelu v Claudovi nevidím",
                                     done ? Palette.done : Palette.warning)
            }
        }
    }

    private func cycleEffort() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let label = ClaudeUI.cycleEffort()
            DispatchQueue.main.async {
                guard let self else { return }
                // "Model: Opus 5.5 High" → "High"
                if let level = label?.components(separatedBy: " ").last {
                    self.touchBar.setEffortLabel(level)
                } else {
                    self.touchBar.flash("Úsilí v Claudovi nevidím", Palette.warning)
                }
            }
        }
    }

    /// Opens the first session that waits for you, in Claude and on the bar.
    private func openWaiting() {
        guard let session = lastSnapshot.sessions.first(where: { $0.activity == .waiting }) else { return }
        selectedSession = session.url
        refresh()
        ClaudeApp.activate()
        openInClaude(session.title)
    }

    private func setMode(_ mode: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let done = ClaudeUI.setMode(mode)
            DispatchQueue.main.async {
                guard let self else { return }
                if done {
                    self.touchBar.flash("✓ Režim: " + mode, Palette.done)
                    if let url = self.lastSnapshot.sessionURL { self.hookStates[url]?.mode = mode }
                    self.refresh()
                } else {
                    self.touchBar.flash("Přepínač režimu v Claudovi nevidím", Palette.warning)
                }
            }
        }
    }

    // MARK: - Hooks

    private func handleHook(_ event: HookEvent) {
        guard let url = event.transcriptURL else { return }
        let now = Date()
        var state = hookStates[url] ?? HookState(activity: .idle, time: now)
        // Every hook carries the session's permission mode; keep it current.
        if let mode = ClaudeUI.modeName(event.permissionMode), mode != state.mode {
            state.mode = mode
            hookStates[url] = state
        }
        state.time = now
        switch event.name {
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure":
            state.activity = .working
            state.tool = nil
            // You wrote something new in that chat: its card is answered.
            if event.name == "UserPromptSubmit", card?.transcriptURL == url { setCard(nil) }
        case "PreToolUse":
            state.activity = .working
            state.tool = event.toolName
            if let tool = event.toolName, PlanState.tools.contains(tool), let input = event.toolInput {
                let plan = plans[url] ?? PlanState()
                plan.apply(input)
                plans[url] = plan
            }
            if Settings.cards, let newCard = ClaudeUI.Card.from(tool: event.toolName, input: event.toolInput, transcript: url) {
                if !newCard.buttons.isEmpty { setCard(newCard) }
                if newCard.readsScreen { readCardFromScreen(newCard) }
            }
        case "PermissionRequest":
            state.activity = .waiting
        case "Notification":
            switch event.notificationType {
            case "permission_prompt"?, "elicitation_dialog"?, "agent_needs_input"?:
                state.activity = .waiting
            default:
                return
            }
        case "Stop", "StopFailure":
            state.activity = .done
            state.tool = nil
        case "SessionStart", "SessionEnd":
            state.activity = .idle
            state.tool = nil
        default:
            return
        }
        hookStates[url] = state
        refresh()
    }

    // MARK: - Cards

    /// Shows (or clears) a card from Claude's chat on the Touch Bar.
    private func setCard(_ newCard: ClaudeUI.Card?, sound: Bool = true) {
        let hadCard = card != nil
        card = newCard
        touchBar.setCard(newCard)
        guard let newCard else {
            // A card that popped up over another app goes away with it.
            if hadCard && !claudeFrontmost && !autoPresented { schedulePopHide(after: 2) }
            return
        }
        HookLog.write("Karta na Touch Baru: \(newCard.title) [\(newCard.buttons.joined(separator: " | "))]")
        if claudeFrontmost {
            touchBar.present()
        } else {
            touchBar.needsAttention = true
            if sound { Sounds.play("Pop") }
            popHide?.cancel()
            touchBar.present()
        }
        // Cards nobody answers shouldn't sit on the bar forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + newCard.lifetime) { [weak self] in
            if self?.card?.id == newCard.id { self?.setCard(nil) }
        }
    }

    /// The box renders a moment after the hook fires; then add the app's own
    /// buttons (Commit, Create PR…) from the same box, found through a reply
    /// label we already know. Only buttons that box really contains are used.
    private func readCardFromScreen(_ base: ClaudeUI.Card) {
        guard KeySender.isTrusted, let anchor = base.buttons.first else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            let labels = ClaudeUI.siblingButtons(of: anchor)
            DispatchQueue.main.async {
                guard let self, labels.count > base.buttons.count else { return }
                // Only update the card that is still showing.
                guard self.card?.id == base.id else { return }
                self.setCard(base.withButtons(Array(labels.prefix(3))), sound: false)
            }
        }
    }

    private func pressCardButton(_ label: String) {
        if let title = card?.openSession {
            setCard(nil)
            ClaudeApp.activate()
            openInClaude(title)
            return
        }
        let submit = card?.submit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pressed = ClaudeUI.press(label)
            if pressed, let submit {
                // Give the app a moment to show its Submit button.
                Thread.sleep(forTimeInterval: 0.35)
                pressed = ClaudeUI.press(submit)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if pressed {
                    self.setCard(nil)
                    self.touchBar.flash("✓ " + label, Palette.done)
                    if !self.claudeFrontmost && !self.autoPresented { self.schedulePopHide(after: 2) }
                } else if !KeySender.isTrusted {
                    self.touchBar.flash("Povol aplikaci Zpřístupnění v Nastavení systému", Palette.warning)
                } else {
                    self.touchBar.flash("Tlačítko „\(label)“ nevidím, otevři ten chat v Claudovi", Palette.warning)
                }
            }
        }
    }

    private func approvalsChanged(_ list: [ApprovalRequest]) {
        touchBar.setApprovals(list)
        detail.model.approvals = list
        let grew = list.count > approvalCount
        approvalCount = list.count

        if grew && claudeFrontmost {
            // The app shows its own dialog at the same time; either answer wins.
            touchBar.present()
        } else if grew {
            touchBar.needsAttention = true
            Sounds.play("Ping")
            popHide?.cancel()
            touchBar.present()
        } else if list.isEmpty && !claudeFrontmost && !autoPresented {
            // After the 1.5 s "✓ Povoleno" confirmation.
            schedulePopHide(after: 2)
        }
        refresh()
    }

    /// Hold permission requests for the Touch Bar only when you'd otherwise
    /// miss them; in Claude itself its own dialog is the better place.
    private func updateHold() {
        let hold = Settings.approvals && (!claudeFrontmost || Settings.approvalsInClaude)
        hooks.holdsApprovals = hold
        if !hold { hooks.releaseAll() }
    }

    // MARK: - Notifications

    private func notifyTransitions(_ snapshot: Snapshot) {
        var finished: SessionInfo?
        var started = false
        for session in snapshot.sessions {
            let before = previousActivity[session.url]
            if before == .working && session.activity == .done { finished = session }
            if before != nil && before != .waiting && session.activity == .waiting { started = true }
            previousActivity[session.url] = session.activity
        }

        if let url = snapshot.sessionURL, snapshot.contextFraction >= 0.9, !warnedContext.contains(url) {
            warnedContext.insert(url)
            if !claudeFrontmost { popBriefly(sound: "Funk") }
        }

        guard !claudeFrontmost else { return }
        if let finished {
            touchBar.needsAttention = true
            Sounds.play("Glass")
            // "✓ Hotovo: <session> │ Otevřít" — one tap takes you to that chat.
            if Settings.popOnDone && card == nil && hooks.approvals.isEmpty {
                setCard(.finished(finished), sound: false)
            }
        } else if started && snapshot.approval == nil {
            // Waiting without a hook request (e.g. hooks off): blink only.
            touchBar.needsAttention = true
        }
    }

    /// Shows the bar for a few seconds over whatever you're doing.
    private func popBriefly(sound: String) {
        Sounds.play(sound)
        guard !touchBar.isPresented else { return }
        touchBar.present()
        schedulePopHide(after: 8)
    }

    private func schedulePopHide(after seconds: TimeInterval) {
        popHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.claudeFrontmost, !self.autoPresented, self.hooks.approvals.isEmpty,
                  self.card == nil || self.card?.openSession != nil else { return }
            self.touchBar.minimize()
        }
        popHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Frontmost app

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handleFrontmost(app)
    }

    private func handleFrontmost(_ app: NSRunningApplication) {
        // Our own detail panel taking focus shouldn't hide the bar.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        claudeFrontmost = app.bundleIdentifier == ClaudeApp.bundleID
        touchBar.claudeFrontmost = claudeFrontmost
        if !touchBar.isPresented { touchBar.ensureTrayIcon() }
        updateHold()

        if claudeFrontmost {
            touchBar.needsAttention = false
            popHide?.cancel()
            if Settings.autoShow {
                touchBar.present()
                autoPresented = true
            }
            refresh()
        } else if autoPresented {
            autoPresented = false
            // A question or approval still waiting for you follows you out of
            // Claude (compact, next to brightness and volume).
            if hooks.approvals.isEmpty && card == nil { touchBar.minimize() }
        }
    }
}
