# Agent dashboards: benchmark for Ping

Researched 2026-11-14. Facts come from each product's own site, README or docs, unless marked *(3rd-party)*. These are vendor claims and none were tested hands-on.

Ping today: notch dot per Claude Code session (working / needs you / your turn), hover to expand into a list, an Allow/Deny card for permission requests, fed by hooks over a Unix socket.

## At a glance

| App | Form | State shown as | Jump / reply | Scale | Price |
|---|---|---|---|---|---|
| Obeya | Desktop canvas (Mac/Win/Linux) + local web UI | Card colour: working / waiting / approved | Open card; push-to-talk voice; phone over VPN | Conflict-aware queue, SSH remote slots | Free, MIT |
| Paradev (ex-Superset) | Desktop GUI (macOS; Linux beta) + CLI/MCP + iOS | Sidebar grouped by status; iOS Live Activity | Open workspace; mobile reply (Pro) | "100+ agents", worktree per task | Free; Pro $20/mo; Team $60/mo |
| Vibe Kanban | Web/local kanban | Task cards on board columns | Open task; diff UI with comments | Parallel or sequential tasks | Free, Apache-2.0 *(3rd-party)* |
| Conductor | Mac desktop app | Sidebar "needs input" signal | Click workspace, type in chat | Workspace per task; cloud workspaces | Free; cloud on paid plans |
| cmux | Native macOS terminal (libghostty) | Ring around pane, sidebar unread badge, macOS notification | Click pane / sidebar | Many panes + workspaces | Free, open source |
| Claude Squad | Terminal TUI (tmux) | Session list | `↵` attach, `ctrl-q` detach | tmux session + worktree each | Free, AGPL-3.0 |
| jmux | tmux wrapper TUI | Sidebar badges RUNNING/WAITING/COMPLETE + timer, `!` needs you | `Ctrl-Shift-↑/↓`; Command Center grid you can type into; `jmux ctl send-keys` | Saved views ("Needs you"), parked rows | Free, AGPL-3.0 |
| ccmux | Rust terminal multiplexer | Orange pane border when Claude runs | Click / keys to focus pane | Max 16 panes per tab | Free, MIT |
| Vibe Island | Notch app | Notch list, expands for prompts | Exact tab/split jump in ~8 terminals; answer questions, approve plans | Claims 30 agents | $19.99 one-time |
| Claude Statistics | Notch + menu bar | Grouped by project; idle pulse | tty / surface-id jump; Allow/Deny cards | Project groups | Free, MIT |
| CodeIsland | Notch | Small indicator → full panel | Per-session jump button; answer questions via `cmux send` | Session list, subagent badges | Free, open source |
| AgentPeek | Notch | Pill → tabbed panel | Allow / Deny / Deny with feedback / Always allow | "Unlimited" | $9 one-time |
| Chimlo | Notch | Row per session, attention-first sort | Answer questions; allow once / for session | Scrollable list | Free, open source |

## The apps

### Obeya (obeya.si)
- **What:** Open-source (MIT) desktop app for macOS, Windows and Linux, plus a browser UI on `127.0.0.1:4417`. Runs your own Claude Code or Codex login. Each task is a card on a free-form canvas.
- **State:** Card colour shows working, waiting for you, or approved. Cards stay where you place them (no column shuffling). A finished card shows a narrated demo video with chapters, or a page for visual output, plus a short report.
- **Jump / reply:** Open the card, then approve or say what to change. Push-to-talk (hold space) sends speech to the card you're viewing. Pause the demo on a frame and your feedback goes to the agent with that frame. Phone access over your own VPN (e.g. Tailscale) lists cards waiting for you and lets you approve, answer or dictate a new task.
- **Scale:** Each agent gets its own clone or worktree. Obeya checks what each card will touch against what's running: independent cards start, colliding ones wait (hover shows why; draw arrows to set order). Overflow goes to other machines over SSH.
- **Pricing:** Free. No pricing page.
- **Standout:** Agent-recorded demo videos as the review unit; PR review cards that read the diff before running code; works in plain folders without git.

### Paradev, formerly Superset (paradev.com)
- **What:** Desktop GUI for running any CLI agent (Claude Code, Codex, OpenCode, Gemini CLI, Cursor Agent…) in git worktrees. macOS first, Linux AppImage experimental. Also a CLI, TypeScript SDK, MCP server and iOS app. MIT, ~16k stars. superset.sh redirects to paradev.com, and the site confirms the rename.
- **State:** Sidebar groups agents by status ("In Progress", "Ready for Review"). The iOS Live Activity on the Lock Screen and Dynamic Island shows need you / working / ready for review. It only updates while the app is open, and push notifications are announced but not shipped. `superset ls` prints status.
- **Jump / reply:** Open the workspace's agent terminal. Reply from mobile when agents run in the cloud or on an always-on host. Design Mode: click an element in the in-app browser and send it to an agent with a note.
- **Scale:** Headline claims 100+ agents. One worktree and branch per task. Changes and PR panes for commit, push, checks and merge.
- **Pricing:** Free (local). Pro $20/user/mo (remote, automations, mobile). Team $60/user/mo (cloud workspaces). Ultra $200. Enterprise custom.
- **Standout:** Status grouping in the sidebar; Live Activity on the phone; automations triggered by PRs, Slack, Linear or Sentry.

### Vibe Kanban
- **What:** Open-source (Apache-2.0) kanban board that runs locally and orchestrates coding agents (Claude Code, Codex, Gemini CLI, OpenCode…). *(3rd-party listings; the company reportedly shut down its hosted cloud, and the project is now community-maintained.)*
- **State:** Each task is a card whose column tracks status.
- **Jump / reply:** Open a task: each has its own worktree, branch, terminal, dev server and browser preview. Review output in a diff UI with inline comment threads, then create a PR.
- **Scale:** Run agents in parallel or in sequence; switch agent per task; central MCP config.
- **Pricing:** Free open source. The Pro / cloud tiers listed by some directories appear discontinued.
- **Standout:** Task board as the mental model; one place for all agents' MCP configs.

### Conductor (conductor.build)
- **What:** Mac-only desktop app by Melty Labs for running Claude Code, Codex, Cursor and OpenCode in parallel, each in a worktree workspace. Conductor Cloud runs workspaces in sandboxes that keep going after the laptop closes.
- **State:** A sidebar flags sessions that need input. Permission prompts are approved inside the workspace chat. No documented OS notifications.
- **Jump / reply:** Click a workspace in the sidebar and type in its chat. Inline diff comments become attachments you send back to the agent.
- **Scale:** No stated limit; one workspace per independent task, 10 ports each.
- **Pricing:** Free (bring your own subscription). Cloud workspaces on Pro/Teams/Enterprise.
- **Standout:** Keyboard-first (`⌘⇧N` new, `⌘⇧D` diff, `⌘⇧P` PR, `⌘/` shortcut list); Checks tab with CI and merge blockers; multiplayer presence dots in Cloud.

### cmux (cmux.com, manaflow-ai/cmux)
- **What:** Free, open-source native macOS terminal built on libghostty, aimed at running many agents. Reads your Ghostty config.
- **State:** When a pane needs attention it gets a coloured ring, an unread badge in the sidebar, a notification popover and a macOS notification. It picks up OSC 9/99/777 sequences, and `cmux notify` can be called from agent hooks.
- **Jump / reply:** Click the pane or sidebar entry; `cmux send` lets other tools type into a pane (CodeIsland uses this to answer questions from the notch).
- **Scale:** Split panes plus workspaces in a sidebar.
- **Standout:** Born from the exact problem Ping targets: macOS notifications that don't say *which* agent needs you.

### Claude Squad (smtg-ai/claude-squad)
- **What:** Go terminal TUI (`cs`) on top of tmux and gh. AGPL-3.0, ~8.8k stars. Works with Claude Code, Codex, Gemini, Aider.
- **State:** A list of sessions; the README doesn't document a state indicator.
- **Jump / reply:** `↵`/`o` attaches to the session's tmux pane to reprompt, `ctrl-q` detaches. `N` starts a session with a prompt.
- **Scale:** Each session gets its own tmux session and worktree. `c` commits and pauses, `r` resumes, `D` kills.
- **Standout:** Pause/resume a session to free resources; `s` commits and pushes the branch; experimental `--autoyes`.

### jmux (jarredkenny/jmux)
- **What:** tmux wrapper TUI, AGPL-3.0, young (~85 stars). Works with Claude Code, Codex, pi and others.
- **State:** Sidebar badges RUNNING / WAITING / COMPLETE with an elapsed timer; green `●` for new output, orange `!` for needs you; CI glyphs. Claude Code reports through hooks. State lives in tmux user options (`@jmux-agent-state`, `@jmux-agent-state-since`, `@jmux-agent-pane`) and is scoped per pane, so two agents in one session don't clash.
- **Jump / reply:** `Ctrl-Shift-↑/↓` cycles sessions. `Ctrl-a C` opens the Command Center, a grid of live mirrors you can type into. Scripted reply via `jmux ctl pane send-keys`; `jmux ctl agent watch` streams state changes as JSONL.
- **Scale:** Saved views like "Active" and "Needs you"; workflow stages collapse idle sessions into one "Parked (n)" row without killing them.
- **Standout:** Open state protocol anyone can write to; Linear/GitHub issue → worktree + agent in one key.

### ccmux (shin-sibainu)
- **What:** Rust terminal multiplexer for Claude Code, no tmux needed. MIT. (Several unrelated projects share the name; this is the npm `ccmux-cli` one. The PyPI `ccmux` couldn't be read.)
- **State:** A pane's border turns orange and its title becomes `claude [N]` when Claude runs (detected from OSC window-title sequences). The status bar shows model and context usage. No needs-input detection.
- **Jump / reply:** Click or key to focus a pane and type into it.
- **Scale:** Hard cap of 16 panes per tab.
- **Standout:** Detects Claude passively from terminal title sequences, with no hooks.

### Notch and menu-bar monitors (Ping's direct competitors)
- **Vibe Island** (vibeisland.app, commercial, macOS 14+): notch list that expands for permission prompts, AskUserQuestion (multiple choice and free text) and ExitPlanMode plans rendered as Markdown with approve/feedback. Claims exact tab and split-pane jump (incl. tmux and `tmux -CC`) for iTerm2, Ghostty, Terminal.app, Warp, WezTerm, Kitty, Zellij and VS Code/Cursor terminals; other terminals get app activation. Falls back to a top-centre bar on Macs without a notch. 8-bit sound per event with importable sound packs. Shows 5h/7d Claude usage with reset timers, SSH remote monitoring. $19.99 one-time, 2-day trial.
- **Claude Statistics** (sj719045032/claude-statistics, MIT): "Notch Island" groups Claude Code, Codex and Gemini sessions by project with live status; idle sessions waiting for input get a subtle pulse. Jump: Ghostty by surface id (falls back to window + tab, then cwd), iTerm2 and Terminal.app by tty match, Kitty/WezTerm/Alacritty by their CLIs, triggered by click or Return. Allow/Deny cards via PermissionRequest hooks. Also usage, cost analytics and transcript search in a menu-bar panel.
- **CodeIsland** (xmqywx/CodeIsland, free): collapsed indicator → full panel with session list, usage bars and chat/diff detail. Jump via AppleScript (iTerm2 session-level, Ghostty window-level), cmux workspace, app activation elsewhere. Answers AskUserQuestion with notch buttons, sending the choice with `cmux send` (cmux only). Suppresses popups for the session whose tab you're already looking at. Tracks subagents as badges.
- **AgentPeek** ($9 one-time, Apple silicon) *(3rd-party write-up)*: pill → panel with Sessions, Quick Routes (open project folders) and Local Servers (detects dev servers on ports 3000–9999 and lets you open or stop them). Permission card offers Allow, Deny, Deny with feedback, Always Allow, Open Terminal.
- **Chimlo** (kraten/chimlo, free): row per session showing project, provider, status and recent activity, with items needing attention sorted to the top. Permission card shows the action, file path and a preview of the command or change; options deny, allow once, allow for this session.
- Also seen, not researched: Agent Island, Glint, Vibe Notch (same hooks + Unix socket design as Ping), Notchy, Claude Visor, Notchcode.

## Ideas worth borrowing for Ping (ranked)

1. **Precise jump to the session's tab, with a fallback ladder.** Match by tty for iTerm2 and Terminal.app, by surface id for Ghostty, and by tmux pane; otherwise just activate the app. *(Claude Statistics, Vibe Island)* This is the first backlog item, and these apps show it's doable per terminal.
2. **Answer AskUserQuestion and plans from the notch, not just permissions.** Show question options as buttons, and plan approval with a "send feedback" field. *(Vibe Island, CodeIsland)* Ping's existing card is most of the UI already.
3. **Richer permission card.** Add a preview of the command or diff, "allow for this session", and "deny with feedback". *(Chimlo, AgentPeek)* Cheap, and it makes Allow/Deny decisions safer.
4. **Attention-first ordering and grouping.** Needs-you sorts to the top, group by project, park idle sessions into one collapsed row. *(Chimlo, Claude Statistics, jmux "Parked (n)")* This matches the "scale to tens" backlog item.
5. **Suppress alerts for the session you're already looking at.** If the frontmost tab is that session, don't pop the notch. *(CodeIsland)* This is a cheap complement to the "seen state" backlog item.
6. **Elapsed time per state.** "Waiting 4m" shows which agent has been blocked longest. *(jmux)*
7. **Distinct sound per event.** Different sounds for needs-you and done, so you don't have to look. *(Vibe Island, cmux notifications)*
8. **Typed replies via a tmux/cmux send path.** `tmux send-keys` / `cmux send` to the matched pane is the simplest proven route for "answer from the notch". *(jmux, CodeIsland)*
9. **Fallback bar on Macs without a notch.** Put a top-centre pill on external displays. *(Vibe Island, Claude Statistics)*
10. **Usage strip.** Show 5h/7d Claude limits with reset times in the expanded view. *(Vibe Island, CodeIsland, Claude Statistics)* This is nice to have, but outside Ping's core.

Skip for now: worktree management, diff review, kanban/canvas, cloud workspaces (Paradev, Conductor, Vibe Kanban, Obeya). Those are orchestrators. Ping's niche is the at-a-glance attention layer that sits over whatever runs the agents.

## Sources
- https://obeya.si/, https://obeya.si/watch-the-demo/
- https://paradev.com/, https://paradev.com/llms.txt, https://paradev.com/pricing
- https://www.conductor.build/llms-full.txt, https://www.conductor.build/docs/
- https://cmux.com/, https://github.com/manaflow-ai/cmux
- https://github.com/smtg-ai/claude-squad
- https://github.com/jarredkenny/jmux, https://raw.githubusercontent.com/jarredkenny/jmux/main/docs/agent-integration.md
- https://shin-sibainu.github.io/ccmux/docs/en
- https://vibeisland.app/, https://vibeisland.app/claude-code/
- https://github.com/sj719045032/claude-statistics
- https://dev.to/krisying/i-turned-my-macbooks-notch-into-a-control-center-for-ai-coding-agents-2o57 (CodeIsland)
- https://chatgate.ai/post/agentpeek
- https://www.producthunt.com/posts/chimlo
- Vibe Kanban: https://www.ycombinator.com/companies/vibe-kanban, https://aiidelist.com/ide/vibe-kanban (3rd-party)
