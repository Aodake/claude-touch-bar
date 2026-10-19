# Security Policy

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Report them privately through GitHub instead: go to the repository's **Security** tab and click **Report a vulnerability** ([direct link](https://github.com/Aodake/claude-touch-bar/security/advisories/new)). Only the maintainer can see the report.

Please include what you found, how to reproduce it and which version or commit you used. You'll get an answer as soon as possible, usually within a few days. Once a fix is out, the advisory is published and you're credited unless you prefer otherwise.

## Supported versions

Only the latest release and the `main` branch get security fixes.

## What the app does with your data

Claude Touch Bar is a local-only utility. In short:

- **One network request, and you can turn it off.** No telemetry, no analytics, no update checks, and none of your data ever leaves your Mac. The only request: with the Czech UI and *Ukazovat Kč* (Show Kč) on, the app downloads the Czech National Bank's public USD/CZK rate file (`https://www.cnb.cz/…/denni_kurz.txt`) at most every 6 hours, without cookies and without sending anything about you. Turn *Ukazovat Kč* off in General (or use the English UI) and the app makes no network requests at all.
- **Reads transcripts, read-only.** Token counts, cost estimates and session status come from the transcript files the Claude desktop app writes to `~/.claude/projects/**.jsonl`. The app only reads them and never changes them.
- **No credentials.** The app never reads, stores or sends your Claude login, API keys, tokens or anything from the Keychain.
- **Hooks over a local Unix socket.** If you turn on hooks, the app adds entries to `~/.claude/settings.json` (your other hooks stay, and a backup is saved as `settings.json.bak-claudetouchbar`). The hooks run the app's own binary, which passes events to the running app over a Unix domain socket in `~/Library/Application Support/ClaudeTouchBar/`. The socket isn't reachable from the network. Hooks can be removed at any time from the app window or with `--uninstall-hooks`.
- **Local files it writes:** its settings (macOS user defaults), a hook log in `~/Library/Application Support/ClaudeTouchBar/hooks.log`, and, if you turn on launch at login, `~/Library/LaunchAgents/local.ClaudeTouchBar.plist`.
- **Git, only on demand.** For the ↑ Commit and push item it runs `/usr/bin/git` locally to count changes in the folder you chose. The commit and push themselves are done by Claude when you tap the button.

## Permissions and why

| Permission | Why it's needed |
|---|---|
| **Accessibility** (System Settings → Privacy & Security → Accessibility) | To control the Claude desktop app's window from the Touch Bar: bring it to the front, press Allow / Deny, answer cards, switch sessions, send Stop, New and similar actions. Without it the Touch Bar still shows status and spend, but the buttons that act on Claude's window don't work. |

The app asks for nothing else: no Full Disk Access, no Screen Recording, no microphone, camera, contacts or location.

## Private Touch Bar API

Showing the bar over other apps and the Control Strip icon use private macOS Touch Bar API (as MTMR and Pock do). This is why the app can't be distributed through the Mac App Store.

## Code signing

Release builds are signed ad hoc and are **not notarized** by Apple, so macOS warns on first launch. If you'd rather not trust a prebuilt binary, build it yourself from source with `./build.sh`; the whole app is a few Swift files in `Sources/`.
