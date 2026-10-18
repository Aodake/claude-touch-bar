import AppKit

/// Finds and presses buttons inside the Claude app's window through the
/// Accessibility API, so a card's buttons can be mirrored on the Touch Bar.
/// The app is Electron, which only exposes its UI tree once asked to via
/// AXManualAccessibility.
enum ClaudeUI {
    struct Button {
        let label: String
        let element: AXUIElement
    }

    private static func application() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeApp.bundleID).first
        else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return element
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        (attribute(element, name) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// Visible text of an element: its title, description, or the text inside it.
    private static func label(_ element: AXUIElement, depth: Int = 0) -> String? {
        if let title = string(element, kAXTitleAttribute) { return title }
        if let description = string(element, kAXDescriptionAttribute) { return description }
        if let value = string(element, kAXValueAttribute) { return value }
        guard depth < 3 else { return nil }
        let parts = children(element).compactMap { label($0, depth: depth + 1) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Every button in Claude's windows, in on-screen order.
    static func buttons(limit: Int = 40_000) -> [Button] {
        guard let app = application() else { return [] }
        let windows = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var result: [Button] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard visited < limit, depth < 80 else { return }
            visited += 1
            // Question options render as toggle buttons (AXCheckBox).
            let pressable: Set<String> = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole]
            if let role = string(element, kAXRoleAttribute), pressable.contains(role),
               let text = label(element)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                result.append(Button(label: text, element: element))
                return
            }
            for child in children(element) { walk(child, depth: depth + 1) }
        }
        for window in windows { walk(window, depth: 0) }
        return result
    }

    /// Presses the last button labelled `label` (the newest card sits lowest).
    /// Falls back to a button whose text starts with it, since option buttons
    /// often carry their description too.
    @discardableResult
    static func press(_ label: String) -> Bool {
        guard KeySender.requestTrust() else { return false }
        let wanted = normalize(label)
        let all = buttons()
        let button = all.last { normalize($0.label) == wanted } ?? all.last { normalize($0.label).hasPrefix(wanted) }
        guard let button else { return false }
        return AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
    }

    /// Every element with one of `roles`, with its visible text.
    static func elements(roles: Set<String>, skipMenuBar: Bool = false, limit: Int = 40_000) -> [Button] {
        guard let app = application() else { return [] }
        var roots = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        roots += children(app).filter { child in
            !roots.contains(child) && !(skipMenuBar && string(child, kAXRoleAttribute) == kAXMenuBarRole as String)
        }
        var result: [Button] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard visited < limit, depth < 80 else { return }
            visited += 1
            if let role = string(element, kAXRoleAttribute), roles.contains(role),
               let text = label(element)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                result.append(Button(label: text, element: element))
            }
            for child in children(element) { walk(child, depth: depth + 1) }
        }
        for root in roots { walk(root, depth: 0) }
        return result
    }

    // MARK: - Permission mode

    /// Modes the picker offers (its items read "Auto Claude handles…" etc.).
    static let modeLabels = ["Auto", "Manual", "Accept edits", "Plan", "Bypass permissions"]

    /// Models offered on the Touch Bar, as Claude's model menu names them.
    static let touchBarModels = ["Opus 5.5", "Fable 5.1", "Sonnet 5.5", "Haiku 5.5"]

    /// Effort isn't a submenu: its menu item moves effort one level per press.
    /// Returns the picker's new label, e.g. "Model: Opus 5.5 High".
    static func cycleEffort() -> String? {
        guard KeySender.requestTrust(), let popup = popUp("Model:") else { return nil }
        AXUIElementPerformAction(popup.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        guard let effort = elements(roles: menuItemRoles, skipMenuBar: true)
            .first(where: { normalize($0.label).hasPrefix("effort") }) else {
            cancelMenus()
            return nil
        }
        AXUIElementPerformAction(effort.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.4)
        cancelMenus()
        return popUp("Model:")?.label
    }

    /// Modes offered on the Touch Bar. Bypass is left out on purpose: one
    /// stray tap shouldn't turn off every permission prompt.
    static let touchBarModes = ["Manual", "Auto", "Accept edits", "Plan"]

    /// The hook's `permission_mode` as the picker names it.
    static func modeName(_ hookMode: String?) -> String? {
        switch hookMode {
        case "default"?, "manual"?: return "Manual"
        case "auto"?: return "Auto"
        case "acceptEdits"?: return "Accept edits"
        case "plan"?: return "Plan"
        case "bypassPermissions"?: return "Bypass"
        default: return nil
        }
    }

    /// "Auto" matches "Auto" and "Auto Claude handles…", never "AutoFill".
    static func isMode(_ label: String, _ mode: String) -> Bool {
        let text = normalize(label), wanted = normalize(mode)
        return text == wanted || text.hasPrefix(wanted + " ")
    }

    private static func modePicker() -> Button? {
        elements(roles: [kAXPopUpButtonRole]).first { picker in modeLabels.contains { isMode(picker.label, $0) } }
    }

    private static func openMenuItems() -> [Button] {
        elements(roles: [kAXMenuItemRole, "AXMenuItemRadio", kAXRadioButtonRole, kAXCheckBoxRole], skipMenuBar: true)
    }

    /// The mode shown in the open chat's picker, e.g. "Accept edits".
    static func currentMode() -> String? {
        guard let label = modePicker()?.label else { return nil }
        return modeLabels.first { isMode(label, $0) } ?? label
    }

    /// Opens the picker, lists every item, then closes it by choosing the
    /// current mode again.
    static func availableModes() -> [String] {
        guard let picker = modePicker() else { return [] }
        AXUIElementPerformAction(picker.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        let items = openMenuItems()
        if let current = currentMode(), let same = items.last(where: { isMode($0.label, current) }) {
            AXUIElementPerformAction(same.element, kAXPressAction as CFString)
        }
        return items.map(\.label)
    }

    /// Switches the open chat's permission mode.
    @discardableResult
    static func setMode(_ mode: String) -> Bool {
        guard KeySender.requestTrust(), let picker = modePicker() else { return false }
        if isMode(picker.label, mode) { return true }
        AXUIElementPerformAction(picker.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        guard let item = openMenuItems().last(where: { isMode($0.label, mode) }) else { return false }
        return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }

    // MARK: - Generic pop-up menus (model picker…)

    /// The pop-up button whose label starts with `prefix`, e.g. "Model:".
    static func popUp(_ prefix: String) -> Button? {
        elements(roles: [kAXPopUpButtonRole, kAXButtonRole]).first { normalize($0.label).hasPrefix(normalize(prefix)) }
    }

    /// Closes any open menu without choosing anything.
    static func cancelMenus() {
        // Claude's menus take AXCancel on their items, not on the menu.
        let open = elements(roles: [kAXMenuRole, kAXMenuItemRole], skipMenuBar: true)
        for element in open.reversed() {
            if AXUIElementPerformAction(element.element, kAXCancelAction as CFString) == .success { break }
        }
    }

    private static let menuItemRoles: Set<String> = [kAXMenuItemRole, "AXMenuItemRadio", kAXRadioButtonRole,
                                                      kAXCheckBoxRole, kAXButtonRole]

    /// Opens the pop-up, returns its items (with "✓ " for the checked one),
    /// and closes it again without changing anything.
    static func menuItems(of prefix: String) -> [String] {
        guard let popup = popUp(prefix) else { return [] }
        let before = Set(buttons().map(\.label))
        AXUIElementPerformAction(popup.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        let items = elements(roles: menuItemRoles, skipMenuBar: true)
            .filter { !before.contains($0.label) }
            .map { item -> String in
                let mark = string(item.element, kAXMenuItemMarkCharAttribute) ?? ""
                return (mark.isEmpty ? "" : "✓ ") + item.label
            }
        cancelMenus()
        return items
    }

    /// Opens the pop-up, then its `submenu` item (e.g. "Effort"), and returns
    /// what that shows. Closes everything again.
    static func submenuItems(of prefix: String, submenu: String) -> [String] {
        guard let popup = popUp(prefix) else { return [] }
        AXUIElementPerformAction(popup.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        let first = elements(roles: menuItemRoles, skipMenuBar: true)
        guard let entry = first.first(where: { normalize($0.label).hasPrefix(normalize(submenu)) }) else {
            cancelMenus()
            return []
        }
        let seen = Set(first.map(\.label))
        AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        let items = elements(roles: menuItemRoles, skipMenuBar: true)
            .filter { !seen.contains($0.label) }
            .map { item -> String in
                let mark = string(item.element, kAXMenuItemMarkCharAttribute) ?? ""
                return (mark.isEmpty ? "" : "✓ ") + item.label
            }
        cancelMenus()
        cancelMenus()
        return items
    }

    /// Opens the pop-up, then `submenu`, and picks `option` there.
    @discardableResult
    static func choose(_ option: String, inSubmenu submenu: String, of prefix: String) -> Bool {
        guard KeySender.requestTrust(), let popup = popUp(prefix) else { return false }
        AXUIElementPerformAction(popup.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        let first = elements(roles: menuItemRoles, skipMenuBar: true)
        guard let entry = first.first(where: { normalize($0.label).hasPrefix(normalize(submenu)) }) else {
            cancelMenus()
            return false
        }
        AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        guard let item = elements(roles: menuItemRoles, skipMenuBar: true).last(where: { isMode($0.label, option) })
        else {
            cancelMenus()
            cancelMenus()
            return false
        }
        return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }

    /// Opens the pop-up and picks the item whose label starts with `option`.
    @discardableResult
    static func choose(_ option: String, in prefix: String) -> Bool {
        guard KeySender.requestTrust(), let popup = popUp(prefix) else { return false }
        AXUIElementPerformAction(popup.element, kAXPressAction as CFString)
        Thread.sleep(forTimeInterval: 0.5)
        let items = elements(roles: menuItemRoles, skipMenuBar: true)
        guard let item = items.last(where: { isMode($0.label, option) }) else {
            cancelMenus()
            return false
        }
        return AXUIElementPerformAction(item.element, kAXPressAction as CFString) == .success
    }

    // MARK: - Sessions

    /// Opens a session from Claude's sidebar by its title.
    @discardableResult
    static func openSession(titled title: String) -> Bool {
        guard KeySender.requestTrust() else { return false }
        // Sidebar rows read "<title>", "<title> <project>" or
        // "<title> Started by Claude from …"; the rename button "<title>, …".
        let wanted = normalize(title)
        let all = buttons()
        let match = all.first { normalize($0.label) == wanted }
            ?? all.first { normalize($0.label).hasPrefix(wanted + " ") }
        guard let match else { return false }
        return AXUIElementPerformAction(match.element, kAXPressAction as CFString) == .success
    }

    /// All buttons in the same box as the button labelled `anchor` (one we
    /// already know from the hook), so app-added ones like Commit come along
    /// but nothing else on screen does.
    static func siblingButtons(of anchor: String) -> [String] {
        let wanted = normalize(anchor)
        guard let found = buttons().last(where: { normalize($0.label).hasPrefix(wanted) }),
              let parent = attribute(found.element, kAXParentAttribute) else { return [] }
        let box = parent as! AXUIElement
        var labels: [String] = []
        func collect(_ element: AXUIElement, depth: Int) {
            guard depth < 3 else { return }
            if let role = string(element, kAXRoleAttribute), role == kAXButtonRole as String,
               let text = label(element)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                labels.append(text)
                return
            }
            for child in children(element) { collect(child, depth: depth + 1) }
        }
        for child in children(box) { collect(child, depth: 0) }
        return labels
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A card Claude put in the chat that waits for a click: a new-session
    /// offer, a question with options, or the next-step buttons.
    struct Card: Identifiable {
        let transcriptURL: URL?
        let title: String
        let buttons: [String]
        /// Pressed after the chosen option, for cards that need confirming.
        var submit: String? = nil
        /// Replace `buttons` with the card's real buttons read from the window.
        var readsScreen = false
        /// A "done" card: its button opens this session in Claude's sidebar.
        var openSession: String? = nil
        /// How long the card stays when nobody answers it.
        var lifetime: TimeInterval = 600
        var id = UUID()
        let created = Date()

        func withButtons(_ labels: [String]) -> Card {
            var copy = Card(transcriptURL: transcriptURL, title: title, buttons: labels, submit: submit)
            copy.id = id
            return copy
        }

        /// "✓ Done: <session>" with a button that opens it.
        static func finished(_ session: SessionInfo) -> Card {
            Card(transcriptURL: session.url, title: L("✓ Hotovo: ", "✓ Done: ") + session.title, buttons: [L("Otevřít", "Open")],
                 openSession: session.title, lifetime: 60)
        }

        /// Built from a PreToolUse hook's tool name and input.
        static func from(tool: String?, input: [String: Any]?, transcript: URL?) -> Card? {
            guard let tool, let input else { return nil }
            switch tool {
            case "mcp__ccd_session__start_session":
                guard let title = input["title"] as? String else { return nil }
                switch input["initiation"] as? String {
                case "offer"?:
                    return Card(transcriptURL: transcript, title: L("Nová session: ", "New session: ") + title, buttons: ["Start", "Do it here"])
                case "own_initiative"?:
                    return Card(transcriptURL: transcript, title: L("Návrh: ", "Suggestion: ") + title, buttons: ["Start"])
                default:
                    return nil
                }
            case "mcp__ccd_turn__wrap_up":
                // Plain replies carry their label. App actions (Commit, Create
                // PR…) show the app's own label, which the hook doesn't know;
                // those are read from the same box on screen, anchored on a
                // known reply (see readsScreen).
                guard let ask = input["ask"] as? String,
                      let actions = input["actions"] as? [[String: Any]], !actions.isEmpty else { return nil }
                let labels = actions.filter { $0["action"] == nil }.compactMap { $0["label"] as? String }
                guard !labels.isEmpty else { return nil }
                let hasAppActions = actions.contains { $0["action"] != nil }
                return Card(transcriptURL: transcript, title: ask, buttons: Array(labels.prefix(3)),
                            readsScreen: hasAppActions)
            case "AskUserQuestion":
                guard let questions = input["questions"] as? [[String: Any]], questions.count == 1,
                      let question = questions.first, question["multiSelect"] as? Bool != true,
                      let options = question["options"] as? [[String: Any]] else { return nil }
                let labels = options.compactMap { $0["label"] as? String }
                guard !labels.isEmpty else { return nil }
                // Picking an option only selects it; Submit sends the answer.
                return Card(transcriptURL: transcript, title: question["question"] as? String ?? L("Otázka", "Question"),
                            buttons: Array(labels.prefix(3)), submit: "Submit")
            default:
                return nil
            }
        }
    }

    /// `ClaudeTouchBar --ax-dump [text]`: writes the buttons it can see, and
    /// with `text` every element mentioning it (role and actions), for checking.
    static func dump(matching term: String? = nil) {
        let started = Date()
        let found = buttons()
        var lines = ["trusted=\(KeySender.isTrusted) buttons=\(found.count) time=\(String(format: "%.2f", Date().timeIntervalSince(started)))s"]
        lines += found.map { "  [\($0.label)]" }
        if let term, let app = application() {
            lines.append("--- elements mentioning \"\(term)\":")
            var visited = 0
            func walk(_ element: AXUIElement, depth: Int) {
                guard visited < 40_000, depth < 80 else { return }
                visited += 1
                let own = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
                    .compactMap { string(element, $0) }.joined(separator: " | ")
                if own.localizedCaseInsensitiveContains(term) {
                    var actions: CFArray?
                    AXUIElementCopyActionNames(element, &actions)
                    let role = string(element, kAXRoleAttribute) ?? "?"
                    let subrole = string(element, kAXSubroleAttribute) ?? ""
                    lines.append("  depth=\(depth) role=\(role) \(subrole) actions=\((actions as? [String]) ?? []) text=\(own.prefix(80))")
                }
                for child in children(element) { walk(child, depth: depth + 1) }
            }
            for window in (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(window, depth: 0) }
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: HookPaths.directory, withIntermediateDirectories: true)
        try? text.write(to: HookPaths.directory.appendingPathComponent("ax-dump.txt"), atomically: true, encoding: .utf8)
    }
}
