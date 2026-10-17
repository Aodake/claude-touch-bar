import AppKit

let arguments = CommandLine.arguments

// Run by Claude Code for every hook event; must stay quick and never fail.
if arguments.contains("--hook") { HookClient.run() }

if arguments.contains("--ax-dump") {
    let index = arguments.firstIndex(of: "--ax-dump")!
    ClaudeUI.dump(matching: index + 1 < arguments.count ? arguments[index + 1] : nil)
    exit(0)
}

if arguments.contains("--ax-modes") {
    let text = "current=\(ClaudeUI.currentMode() ?? "-")\noptions=\(ClaudeUI.availableModes())\n"
    try? text.write(to: HookPaths.directory.appendingPathComponent("ax-modes.txt"), atomically: true, encoding: .utf8)
    exit(0)
}

if arguments.contains("--ax-cancel") {
    ClaudeUI.cancelMenus()
    exit(0)
}

if let index = arguments.firstIndex(of: "--ax-menu"), index + 1 < arguments.count {
    let prefix = arguments[index + 1]
    var text = "popup=\(ClaudeUI.popUp(prefix)?.label ?? "-")\nitems=\(ClaudeUI.menuItems(of: prefix))\n"
    if index + 2 < arguments.count {
        Thread.sleep(forTimeInterval: 0.5)
        text += "submenu=\(ClaudeUI.submenuItems(of: prefix, submenu: arguments[index + 2]))\n"
    }
    try? text.write(to: HookPaths.directory.appendingPathComponent("ax-menu.txt"), atomically: true, encoding: .utf8)
    exit(0)
}

if let index = arguments.firstIndex(of: "--answer"), index + 1 < arguments.count {
    HookClient.answer(arguments[index + 1])
}

if arguments.contains("--install-hooks") || arguments.contains("--uninstall-hooks") {
    do {
        if arguments.contains("--install-hooks") {
            try HookInstaller.install()
            print("Hooky zapnuté v ~/.claude/settings.json (záloha: settings.json.bak-claudetouchbar).")
        } else {
            try HookInstaller.uninstall()
            print("Hooky odebrané z ~/.claude/settings.json.")
        }
        exit(0)
    } catch {
        print("Chyba: \(error.localizedDescription)")
        exit(1)
    }
}

// `--dump` prints what the Touch Bar would show and exits; handy for checking
// the numbers without a Touch Bar.
if arguments.contains("--dump") {
    let s = UsageStore().scanNow()
    func line(_ label: String, _ t: Tokens) {
        print("\(label): vstup \(Format.tokens(t.input)), cache čtení \(Format.tokens(t.cacheRead)), "
            + "cache zápis \(Format.tokens(t.cacheWrite)), výstup \(Format.tokens(t.output)), "
            + "celkem \(Format.tokens(t.total)), \(Format.cost(t.cost))")
    }
    print("Touch Bar API: \(SystemTouchBar.isSupported ? "k dispozici" : "nedostupné")")
    print("Sezení: \(s.title ?? "-") · \(s.project ?? "-") · \(s.modelName) · \(s.activity)")
    print("Kontext: \(Format.tokens(s.contextUsed)) / \(Format.tokens(s.contextWindow)) (\(Format.percent(s.contextFraction)))")
    line("Sezení", s.session)
    line("5 h", s.fiveHours)
    line("Dnes", s.today)
    line("Týden", s.week)
    line("Měsíc", s.month)
    print("Sezení za poslední 3 h: \(s.sessions.map { "\($0.title) (\($0.activity))" }.joined(separator: ", "))")
    print("Posledních 60 min po 5 min: \(s.burn.map { Format.cost($0) }.joined(separator: " "))")
    print("Hooky: \(HookInstaller.isInstalled ? "zapnuté" : "vypnuté")")
    if let cwd = s.cwd {
        if let git = Git.status(at: cwd) {
            print("Git (\(cwd)): větev \(git.branch), změn \(git.changes), k pushnutí \(git.ahead)")
        } else {
            print("Git (\(cwd)): není repozitář")
        }
    }
    if let runway = s.budgetRunway(50) { print("Rozpočet $50 vydrží: \(Format.runway(runway))") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
