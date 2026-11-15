# Backlog

Notchkeeper (formerly Ping).

## Done
- **Releases.** Tag `v*` → GitHub Actions builds Notchkeeper.zip / Notchkeeper.dmg; Homebrew tap thevahidal/tap.
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
- **Sounds and quiet mode.** the "Ping" sound on needs-you, pop on done, reminder when away; quiet mode hides the ears until something needs you.
- **Fallback bar** on displays without a notch.
- **Branch on each row**, read from `.git/HEAD`.
- **Risk flags** on approval cards (`Risk.swift`): red/amber with reasons; red disables "for session", softens Allow and waits 1.5s.
- **Diff preview** for Edit / Write / MultiEdit.
- **Approval log**: `~/.notchkeeper/approvals.log`, JSON lines, 600, rotated at 1 MB.
- **While you were away**: after 10+ minutes idle (Settings: off / 5 / 10 / 15 / 30), only if someone finished or needs you, one card on return with who finished, who waits and files edited. Logic not exercised live yet (needs real idle time).
- **Renamed to Notchkeeper** (v0.2.0): repo, release, tap cask (with `ping` → `notchkeeper` rename), site at thevahidal.github.io/notchkeeper; connecting swaps old Ping hooks.
- **Background agents** (v0.3.0): + in the notch runs `claude --bg -n <name> [-w <name>] <prompt>`; background sessions (from `claude agents --json`) are tagged and open with `claude attach`: clicking again focuses the attached tab; otherwise a new tab in Ghostty's front window (Settings toggle for a new window), else Terminal. Tested: launch and detection with a real agent.
- **Follow-up queue**: messages typed while an agent works go out when the turn ends without a question. Not exercised live end to end.
- **Tell Claude**: deny with a message (`deny-message "<json string>"` → hook `decision.message`). Hook output tested; Claude reading the message not tested live.
- **Settings window.** One place to configure everything (agents, notch, plugins, approvals, command line); opens on first launch, on reopening the app and from the menu bar. Connect/disconnect and plugin toggles tested in a scratch home.
- **Codex and Gemini CLI.** Menu bar → Agents connects each (`~/.codex/hooks.json`, `~/.gemini/settings.json`). Codex approvals work through the same hook; Gemini is status only (its hooks can't answer approvals). Installer tested in a scratch home; event mapping tested with sample events. Not tested against the live CLIs (Codex needs its interactive /hooks approval; Gemini isn't signed in here).
- **Cursor, Copilot CLI, Droid, Kiro CLI, OpenCode, Mistral Vibe.** Status only, connected from Settings like Codex. Each agent's paths, events and field names live in one table (`Agent.Spec` in `HookInstaller.swift`). None of them is hooked before a tool runs: in Cursor, Copilot and Kiro a failing hook there blocks the tool. OpenCode uses a bundled plugin (`hooks/notchkeeper-opencode.js`); Vibe gets a marked block in `~/.vibe/hooks.toml`. Tested: install and removal for all six in a scratch home, keeping the user's own entries; OpenCode live (prompt, tool and done events reach the hook). Not tested live: Cursor (`cursor-agent` wasn't signed in), Copilot, Droid, Kiro, Vibe (not installed).
- **tmux, WezTerm, kitty.** The hook reports the pane; jump and reply go to the exact pane. tmux tested end to end with a stand-in agent; WezTerm and kitty untested (not installed). Unknown terminals come forward by the bundle id in the hook's environment.
- **Never lose track.** Waiting agents kept 24h, sessions saved to `~/.notchkeeper/sessions.json` and restored with a catch-up card, snooze (15m / 1h / tomorrow 9), nudges every 10 min (3 when away). Tested in a scratch home.
- **Chat history in the reply card** (Claude transcripts, last ~14 lines, tail-read).
- **Show on Active Display**: follows the frontmost window's screen; untested on multiple displays (only one here).
- **Items**: `notchkeeper notify` / `notchkeeper run` over the socket. Tested end to end against the running app.
- **Plugins**: `~/.notchkeeper/plugins/*/plugin.json`, events needs-you / done / approval; examples say, journal, ntfy. Path escape rejected; journal and ntfy (local fake server) tested.
- **App icon** (`tools/icon.sh`) and **screenshots** rendered from the real views (`tools/screenshots.sh`).

## Open
- **Signing.** Releases are unsigned (ad-hoc). Add Developer ID signing + notarization to the release workflow; then submit to the official Homebrew cask repo.
- **Verify on a real display.** iTerm2 and Terminal.app scripts are untested end to end (Terminal's automation prompt was pending); no-notch bar only seen in renders.
- **Launch at Login** for the unsigned app: still unverified.
- **brew uninstall hang.** In one test `brew uninstall` hung on the cask's `quit:` step with two copies of the app running. Check with one copy.
- **Clickable options.** AskUserQuestion answers from the notch (needs a reliable send path per terminal).


- **Usage limits.** People watch their 5-hour and weekly limits closely, but only the statusline input (`rate_limits`) or the account token expose them. Revisit if a hook starts carrying them.

- **Native phone companion.** Today: ntfy plugin (notifications only). A real iPhone / Watch app with approvals needs Xcode, an Apple Developer account, and a relay between phone and Mac; approving from a phone means the request leaves the Mac, so it needs end-to-end encryption and pairing. Design before building.
- **Linux.** Hooks and protocol are portable (PROTOCOL.md). Needs a client: GNOME Shell extension or Waybar module listening on the socket, plus Linux terminal jumps (tmux works as is).
- **Chat history for Codex and Gemini** (different transcript formats).
- **Verify the new agents live.** Cursor (a logging test project is easy to rebuild: project `.cursor/hooks.json`), Copilot (PascalCase event names were picked because the docs show `hook_event_name` only for those), Droid, Kiro v3, Vibe (docs don't say what `hook_event_name` holds or whether hooks need an experimental flag).
- **Approvals for the new agents.** Droid (`PreToolUse` permissionDecision), Copilot (`permissionRequest`), Cursor (`beforeShellExecution`, `ask` has open bugs), OpenCode (`permission.asked` event + reply API). Only after seeing each work live.
- **Windsurf and Cline.** Windsurf's hook docs now redirect to Devin Desktop with a different format; Cline's docs describe JS plugins only. Revisit when documented.
- **Agent icons.** Codex, Cursor and Copilot all show "C"; use each app's icon where one is installed.

## Ideas
- Deny with feedback: a text field whose message goes back to Claude.
- Drop a file or screenshot on a row to paste its path into that session.
- Context meter per row (needs the model's context size, which transcripts don't record).
- Per-session color so collapsed dots tell sessions apart.
- Hide while screen sharing (`NSWindow.sharingType`; check it still works with ScreenCaptureKit).
- Phone handoff for approvals when away.
