# Backlog

## Done
- **Releases.** Tag `v*` → GitHub Actions builds Ping.zip / Ping.dmg; Homebrew tap thevahidal/tap.
- **Click an agent to jump to it.** Ghostty, iTerm2 and Terminal focus the exact tab (by tty); Warp, WezTerm, VS Code and the desktop app come forward.
- **Answer from the notch.** Ghostty, iTerm2 and Terminal: types the reply into the pane and presses Enter.
- **Scale to tens of agents.** More than 4 sessions: counts per state when collapsed; the expanded list scrolls.
- **Benchmark agent "office" apps.** See [research/agent-dashboards.md](research/agent-dashboards.md) and [research/what-people-want.md](research/what-people-want.md).
- **Hotkeys.** ⌥Y / ⌥N allow or deny the open approval card.
- **Seen state.** Clicking a "your turn" row (or finishing in the tab you're looking at) dims and parks it.
- **Questions.** A turn ending in a question box turns orange and shows the question; AskUserQuestion too.
- **Desktop approvals.** Verified against the desktop app's Claude Code (2.1.321, `--permission-prompt-tool=stdio`): both prompts show, the first answer wins, Claude cancels the other.
- **Collapsed notch names who needs you.** Right ear: ✋/✓ plus the repo of the most urgent agent, or a pulse while all work. Replaces the bare count.
- **Time in state.** "waiting 4m", "2m ago", or run time on every row.
- **Allow for session.** Echoes Claude's own `permission_suggestions` (addRules only) back with destination `session`. Verified: the second identical call isn't asked again.
- **Plan card.** Shows the ExitPlanMode plan as Markdown and jumps to the session. Approve isn't offered: Claude ignores a hook's allow for ExitPlanMode (verified on 2.1.321).
- **Sounds and quiet mode.** Ping on needs-you, pop on done, reminder when away; quiet mode hides the ears until something needs you.
- **Fallback bar** on displays without a notch.
- **Branch on each row**, read from `.git/HEAD`.
- **App icon** (`tools/icon.sh`) and **screenshots** rendered from the real views (`tools/screenshots.sh`).

## Open
- **Signing.** Releases are unsigned (ad-hoc). Add Developer ID signing + notarization to the release workflow; then submit to the official Homebrew cask repo.
- **Verify on a real display.** iTerm2 and Terminal.app scripts are untested end to end (Terminal's automation prompt was pending); no-notch bar only seen in renders.
- **Launch at Login** for the unsigned app: still unverified.
- **brew uninstall hang.** In one test `brew uninstall` hung on the cask's `quit:` step with two copies of Ping running. Check with one copy.
- **tmux.** Jump and reply via `tmux send-keys` to the pane.
- **Clickable options.** AskUserQuestion answers from the notch (needs a reliable send path per terminal).

## Ideas
- Deny with feedback: a text field whose message goes back to Claude.
- Drop a file or screenshot on a row to paste its path into that session.
- Context meter per row (needs the model's context size, which transcripts don't record).
- Per-session color so collapsed dots tell sessions apart.
- Hide while screen sharing (`NSWindow.sharingType`; check it still works with ScreenCaptureKit).
- Phone handoff for approvals when away.
- Keep the session list across app restarts.
