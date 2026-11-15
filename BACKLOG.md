# Backlog

## Done
- **Click an agent to jump to it.** Ghostty focuses the exact pane (by tty); desktop brings the Claude app forward.
- **Answer from the notch.** Ghostty only: pastes the reply into the pane and presses Enter.
- **Scale to tens of agents.** More than 4 sessions: counts per state when collapsed; the expanded list scrolls.
- **Benchmark agent "office" apps.** See [research/agent-dashboards.md](research/agent-dashboards.md).
- **Hotkeys.** ⌥Y / ⌥N allow or deny the open approval card.
- **Seen state.** Clicking a "your turn" row (or finishing in the Ghostty tab you're looking at) dims and parks it.
- **Questions.** A turn ending in a question box turns orange and shows the question; AskUserQuestion too.

## Open
- **Releases.** GitHub Actions builds Ping.zip / .dmg on each tag; Homebrew tap (`brew install --cask thevahidal/tap/ping`); download button on the site and README. Unsigned for now; add Developer ID signing + notarization later.
- **App icon.** Ping.app has no icon yet.
- **Desktop approvals.** Unverified: does the desktop app wait for the notch card before showing its own prompt? Test with a desktop session in Ask mode.
- **Other terminals.** Terminal.app and iTerm2 adapters for jump and reply (both expose tty to AppleScript); tmux via `send-keys`.
- **Clickable options.** Ghostty: send the picked option. Desktop: only via an Accessibility spike (fragile, needs permission and a .app bundle).

## Ideas (from [agent-dashboards.md](research/agent-dashboards.md) and [notch-apps.md](research/notch-apps.md))
- Plan review card: show the plan as Markdown with Approve / Keep planning.
- Away-aware alerts: a sound when something needs you, escalating when you've been idle.
- Drop a file or screenshot on a Ghostty row to paste its path into that session.
- Context meter per row; git branch and subagent badge.
- Quiet mode: collapsed notch shows nothing until an agent needs you.
- Per-session color or avatar so collapsed dots tell sessions apart.
- Hide while screen sharing or in full-screen video.
- Richer approval card: "allow for this session", "deny with feedback".
- Phone handoff for approvals when away.
- Fallback bar on Macs without a notch.
- Keep the session list across app restarts.
