# Ping

Your Claude Code agents, one glance away. Ping lives in your MacBook's notch and shows what every agent is doing, which one is stuck waiting on you, and lets you answer without switching windows.

<!-- screenshot: notch collapsed and expanded -->

## What it does

- **Live status in the notch.** One dot per agent: violet while working, green when it's your turn, orange when it needs you. A glow under the notch shows the overall mood. With more than four agents the dots turn into counts.
- **Hover to expand.** Each agent gets a row with its session title, repo, what it's doing right now, permission mode (ask, auto, plan, edits, bypass), and model and effort.
- **Approve from the notch.** When Claude asks for permission, a card shows the command. Allow, Deny, or "Use terminal". ⌥Y and ⌥N work while the card is up.
- **Questions.** When a turn ends with a question, the row turns orange and shows the question.
- **Reply without switching** (Ghostty). Type a reply in the notch; Ping sends it to that agent's terminal.
- **Jump to the agent.** Click a row to focus its exact Ghostty tab, or bring the Claude desktop app forward.
- **Subagents.** Running subagents show as indented lines under their parent.
- **Seen state.** Rows you've looked at go dim and move to the bottom.
- **Works in full screen** and on every Space.

### Where each feature works

| | Status | Approve | Questions | Jump | Reply |
|---|---|---|---|---|---|
| Claude Code CLI in Ghostty | ✅ | ✅ | ✅ | ✅ exact tab | ✅ |
| Claude Code CLI in other terminals | ✅ | ✅ | ✅ | — | — |
| Claude desktop app | ✅ | not yet verified | ✅ | brings the app forward | — |

## Install

Requirements: macOS 14+ on a Mac with a notch (Apple silicon), and Claude Code (CLI or desktop app).

**Homebrew**

```bash
brew trust --cask thevahidal/tap/ping && brew install --cask thevahidal/tap/ping
```

Homebrew asks you to trust casks from third-party taps before it loads them; that's the `brew trust` part.

**Download**

[Download Ping.dmg](https://github.com/thevahidal/ping/releases/latest/download/Ping.dmg), open it and drag Ping to Applications.

**First open:** Ping isn't signed with an Apple Developer ID yet, so macOS says it can't verify the developer. Go to System Settings → Privacy & Security and click **Open Anyway** next to Ping. You only need to do this once.

**From source** (needs the Xcode Command Line Tools: `xcode-select --install`)

```bash
git clone https://github.com/thevahidal/ping.git && cd ping
./build.sh
open .build/Ping.app
```

On first launch Ping asks, in the notch, whether to connect to Claude Code. **Connect** copies the two hook scripts to `~/.ping/hooks/` and adds them to `~/.claude/settings.json`. It keeps a backup of your settings next to the original and leaves your other settings and hooks as they are.

Ping has a menu bar icon (〰) for connecting or disconnecting, launch at login, and quit. The first time you click a Ghostty row or reply, macOS asks whether Ping may control Ghostty.

From a script: `Ping.app/Contents/MacOS/Ping --connect` or `--disconnect` edits the hooks and exits.

### Uninstall

With Homebrew, `brew uninstall --zap --cask ping` disconnects Ping from Claude Code, quits it and deletes `~/.ping`.

Otherwise:
1. Menu bar icon → **Disconnect**. This removes only Ping's entries from `~/.claude/settings.json`.
2. **Quit Ping**, then delete `Ping.app` and `~/.ping`.

## How it works

```
Claude Code (CLI or desktop)
   │  runs a hook on each event: tool use, stop, notification, subagent, …
   ▼
~/.ping/hooks/ping-hook.sh   ──►  ~/.ping/ping.sock  ──►  Ping (notch)
~/.ping/hooks/ping-approve.sh ◄── "allow" / "deny" ◄──┘   (only for permission requests)
```

1. Claude Code reads hooks from `~/.claude/settings.json`. The CLI and the desktop app share this file.
2. `ping-hook.sh` forwards each event's JSON to Ping over a local Unix socket and exits right away. It adds the terminal (tty) Claude runs in so Ping can jump to it.
3. `ping-approve.sh` runs only when Claude needs permission. It waits up to 30 seconds for Ping to answer `allow` or `deny` and prints the matching decision for Claude.
4. Ping keeps everything in memory. For session titles, questions and the model name it reads the session's transcript in `~/.claude/projects/`.

## Security

Ping sits in the path of your agent's permission prompts, so it's built to fail safe.

**What data goes where**
- Hook events contain your prompts, the commands Claude runs and the contents of files it edits. They go only to Ping, over a Unix socket in `~/.ping`. Nothing is sent over the network: Ping opens no TCP or UDP connections, has no telemetry and needs no account.
- Ping writes only the socket, its hook scripts in `~/.ping/hooks`, and, when you connect or disconnect, `~/.claude/settings.json` plus a backup. It never rewrites a settings file it can't parse. It reads transcripts only from `~/.claude/projects/`.

**Approvals**
- Ping can only answer a permission request that Claude sends it. It can't invent one or widen what Claude asked for.
- Anything other than exactly `allow` or `deny` means no decision, and Claude shows its normal prompt. That includes Ping not running, a timeout, a crash, or "Use terminal".
- Clicks and hotkeys are ignored for the first 0.7 seconds after a card appears, so a stray keypress can't approve something you haven't read.
- The hotkeys exist only while a card is showing.

**Who can talk to Ping**
- `~/.ping` is `700` and the socket is `600`, so other users on your Mac can't connect. Anyone who can reach the socket could answer approvals, which is why it's locked down this way.
- Hooks run from a private copy in `~/.ping/hooks` (`700`), not from inside the app or a git checkout. Ping refreshes that copy when it starts, so an update to the app updates the scripts.

**Input handling**
- Event fields are treated as untrusted. The terminal id must look like `ttys012` before it reaches an AppleScript. The transcript path must be a `.jsonl` file under `~/.claude/projects/`. Messages over 1 MB are dropped.
- A reply is typed into a terminal only if `claude` is the program currently running there. If Claude has exited, the tab is a plain shell and pressing Enter would run your text as a command, so Ping jumps to the tab instead.

**Known limits**
- Any program running as your user can already change your Claude settings or talk to the socket. Ping doesn't defend against malware on your own account.
- Releases aren't signed with an Apple Developer ID yet, so macOS warns on first open. The app is ad-hoc signed, so macOS tracks Ping's own permissions (like controlling Ghostty).

## Project layout

```
Sources/Ping/      the app (SwiftUI + AppKit, built with plain swiftc)
hooks/             the hook scripts, bundled into the app
build.sh           builds .build/Ping.app
research/          notes on agent dashboards and notch apps
BACKLOG.md         what's done and what's next
```

## License

[MIT](LICENSE)
