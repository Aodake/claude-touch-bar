# Claude Touch Bar

**English** · [Česky](README.cs.md)

Progress, spend and controls for the Claude desktop app, right on your MacBook's Touch Bar, plus a settings window of its own.

```
✳ 1:34 1/8 │ ▬▬▬░ 3/7 ~4:10 │ ▬▬ 720k │ Session 128M $50 │ Today 66M $27 │ ↑ My project ●4 │ ⇄ │ ⋯ │ ⤓
```

- **Live status:** ✳ working, ● waiting for you, ✓ done, with turn time and the tool in use.
- **Approvals from the Touch Bar:** Allow / Deny without switching to Claude.
- **Cards:** questions, the next-step box and new-session offers can be answered right on the Touch Bar, even from another app.
- **Spend:** tokens and estimated cost per session, 5 h, day, week and month, $/h rate, a chart and a daily budget.
- **Controls:** permission mode, model and effort, session switching, Stop, New, Compact and a Commit + push button.
- **Your own layout:** pick and reorder items across three layouts in the app's window.

- **English and Czech:** switch the language in the window (General → Language); by default it follows macOS.

## Requirements

- MacBook Pro with a Touch Bar, macOS 14 or later
- The [Claude](https://claude.ai/download) desktop app, Code tab (Claude Code)
- Xcode Command Line Tools (`xcode-select --install`) to build

## Install

```bash
git clone https://github.com/Aodake/claude-touch-bar.git
cd claude-touch-bar
./install.sh
```

The script builds the app, copies it to `~/Applications`, turns on launch at login and opens the window.

Then:

1. **Turn on hooks** in the window (Claude integration → Turn on). They make the status exact and let you approve and answer from the Touch Bar.
2. **Allow Accessibility** (System Settings → Privacy & Security → Accessibility). It's needed to control Claude's window.
3. *Optional:* create a code-signing certificate named **ClaudeTouchBar Local** (Keychain Access → Certificate Assistant → Create a Certificate, type *Code Signing*). `build.sh` signs with it, so the Accessibility permission survives rebuilds. Without it the app is signed ad hoc and needs the permission again after every build.

## How it behaves

- **In Claude** the bar shows up by itself and takes the whole Touch Bar. **⤓** shrinks it back to the Mac's own Touch Bar.
- **Outside Claude** a **✳** icon stays in the Control Strip. Tap it to bring up the Claude bar in compact size, next to brightness and volume.
- **⌃⌥C** (Control + Option + C) shows or hides the Claude bar from anywhere.
- Approvals and question cards follow you into other apps until you answer them.
- When Claude finishes while you're elsewhere, `✓ Done: <session> │ Open` pops up, a sound plays and ✳ blinks.

## The app window

Open it from Launchpad or Spotlight ("Claude Touch Bar"), or by tapping the numbers on the Touch Bar. Closing the window leaves the app running in the background.

- **Overview:** status, approvals, context, plan progress, spend (session / 5 h / today / week / month), $/h rate, active time, 24 h and 30 day charts, daily budget with a runway estimate, changed files.
- **Touch Bar:** an editor for the three layouts (Compact, Overview, Minimal). Turn items on and off and drag to reorder. ⇄ switches layouts on the Touch Bar itself.
- **Claude integration:** hooks, approvals, cards, sounds, Accessibility permission.
- **Git and Push:** name and folder of the repository for the ↑ button.
- **General:** launch at login, quit.

## Touch Bar items

| Item | Shows / does |
|---|---|
| Status and time | ✳ working, ● waiting, ✓ done; turn time; session position "1/8". Tap to jump to Claude. |
| Plan progress | `3/7 ~4:10` from the step list Claude keeps |
| Context | context usage, orange from 70 %, red from 90 % |
| Compact | above 80 % context; sends `/compact` |
| Spend | session, 5 h, today, week, month (tokens and $) |
| $/h rate, Active time | spend over the last hour, minutes Claude worked today |
| Chart | spend per 5 minutes over the last hour |
| Changed files | how many files Claude edited in the session (list in the window) |
| Waiting sessions | `● 2 waiting`; tap to jump to the first |
| Commit and push | `↑ My project ●4 ↑1`; sends "Commit and push the changes" to the open chat |
| Model picker | Opus / Fable / Sonnet / Haiku and "Effort ▸" (each tap moves effort one level) |
| ⋯ | Allow / Deny, Stop, New, Push, permission mode, model, sessions, details |

## Claude Code hooks

Turn them on in the window or with:

```bash
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --install-hooks
```

They're added to `~/.claude/settings.json`. Your other hooks stay, and a backup is saved as `settings.json.bak-claudetouchbar`. Hooks send events to the app over a local Unix socket. A permission request waits for an answer from the Touch Bar or from Claude itself, whichever comes first. In *Auto* mode Claude doesn't ask for permission, so no approval bar appears. Events are logged to `~/Library/Application Support/ClaudeTouchBar/hooks.log`.

## Where the numbers come from

The Code tab writes session transcripts to `~/.claude/projects/**.jsonl`, and the app only reads them. It sends nothing over the network and never touches your credentials. The Chat tab doesn't store token counts locally, so it isn't counted.

The $ figure is an **estimate at public API prices** (input, output, cache writes and reads, per model). Subscriptions (Pro, Max, Team, Enterprise) aren't billed per token. The number shows what the same work would cost through the API. Prices live in `Sources/Pricing.swift`.

## Handy commands

```bash
# Print what the Touch Bar would show, no Touch Bar needed
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --dump
```

## Uninstall

```bash
"$HOME/Applications/Claude Touch Bar.app/Contents/MacOS/ClaudeTouchBar" --uninstall-hooks; pkill -x ClaudeTouchBar; rm -f ~/Library/LaunchAgents/local.ClaudeTouchBar.plist; rm -rf "$HOME/Applications/Claude Touch Bar.app"
```

## Layout

| File | Contents |
|---|---|
| `Sources/TouchBarController.swift` | builds and renders the Touch Bar |
| `Sources/AppDelegate.swift` | wires everything up, notifications, ⌃⌥C shortcut |
| `Sources/UsageStore.swift` | reads transcripts: tokens, spend, session state |
| `Sources/Hooks.swift` | hook server and client, hook installer |
| `Sources/ClaudeUI.swift` | drives Claude's window through Accessibility, cards |
| `Sources/DetailWindow.swift` | the app window (SwiftUI) |
| `Sources/BarItems.swift` | items and layouts |
| `Sources/SystemTouchBar.swift` | private Touch Bar API |
| `Sources/Pricing.swift` | model price table |

## Technical note

Showing the bar over other apps and the Control Strip icon use private Touch Bar API (as MTMR and Pock do). Controlling Claude's window goes through the Accessibility API. If a future macOS or Claude release changes any of that, the app won't crash; that one feature just stops working.

Unofficial project, not affiliated with Anthropic.

## Support

If it saves you a few window switches and you'd like to say thanks, you can [buy me a coffee via PayPal](https://paypal.me/aodake). Totally optional.

## License

[MIT](LICENSE)
