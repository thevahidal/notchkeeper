# Notch apps: what to borrow

Follow-up to [agent-dashboards.md](agent-dashboards.md), which already covers Vibe Island, Claude Statistics, CodeIsland, AgentPeek and Chimlo. Researched 2026-11-14 from vendor pages, READMEs and third-party write-ups, so treat the feature claims as vendor-stated.

## General notch apps (UX ideas, not agents)
- **NotchNook** (lo.cafe, ~$10/yr): expands on hover into media, calendar and a file **tray** (drop files to park them). On Macs without a notch it can mimic a thin black bar. The Pro edition advertises AI agents and Live Activities.
- **boring.notch** (open source, ~11k stars): music with visualizer, file shelf with AirDrop, calendar, camera mirror, battery, HUD replacement. Hides during full-screen media (reported as flaky).
- **Alcove** ($14): the most "Dynamic Island" feel. Fluid transitions, **swipe gestures**, live activities, custom HUDs, lock-screen presence.
- **DynamicLake Pro** ($17): media keys HUD, **quick reply** to Messages/WhatsApp notifications, drag-drop file actions (compress, share), AirPods alerts.
- **Atoll** (GPL, open source): media, live activities (Focus, screen recording, privacy indicators), system monitors, timers, clipboard, lock-screen widgets.
- **NotchDrop / Droppy** (MIT): notch as a drop zone for files; Droppy adds a floating basket, clipboard and HUDs.

## Agent notch apps not covered before
- **Claude Island / Vibe Notch** (Apache 2.0): same design as Ping (hooks → Unix socket). Session list, approvals, and **chat history rendered as Markdown** in the notch. Forks: Claude Visor, VibeHub (adds a menu-bar mode for Macs without a notch).
- **Notchi** (open source): a **pixel-art sprite per session** that animates idle / working / waiting / sleeping. Optional sentiment reactions. Panel shows an event feed, session time and remaining usage.
- **AgentNotch** (paid): live tool calls, token use and **cost estimates**. Setting for whether the collapsed notch shows ongoing work or **only notifications**. Monitor only, no approvals.
- **Agent Island** (open source, macOS and Windows): built for **walking away**. When a run needs you it fires an alarm window, a notification and a sound. Early versions had opt-in scheduled auto-resume; later versions dropped silent operation.
- **Pushary Isle** ($10/mo): approvals in the notch with **⌃⌘Y / ⌃⌘N**, mirrored to your **phone's lock screen**; answering in one place clears the other. Paid plan adds **permission policies** and an audit trail. Needs an account.
- **CodeIsland** (open source): activity cards with task progress, **git branch** and Markdown replies. iPhone / Apple Watch companions, SSH monitoring, webhooks.
- **Vibe Island** (paid, covered before): its standout is **plan review**. ExitPlanMode shows the full plan as Markdown with Approve or "send feedback".

## Ideas for Ping (ranked by value for effort)
1. **Plan review card.** When Claude asks to exit plan mode, show the plan (Markdown) with Approve / Keep planning. It arrives through the PermissionRequest hook Ping already handles; today the card just says "wants to use ExitPlanMode". *(Vibe Island)*
2. **Away-aware alerts.** Sound when something needs you. If you've been idle for a few minutes, escalate with a notification and a louder alarm. macOS reports idle time without permissions. *(Agent Island, Vibe Island sounds)*
3. **Drop a file on an agent.** Drag a screenshot or file onto a Ghostty row to paste its path into that session. Combines the notch file tray with Ping's reply path. *(NotchNook tray, NotchDrop)*
4. **Context meter per row.** How full each session's context is, read from the transcript's token usage, with a warning near the limit. *(AgentNotch, Notchi)*
5. **Branch and subagents on the row.** Git branch from the session's folder, plus a badge while subagents run. *(CodeIsland)*
6. **Quiet mode.** The collapsed notch shows nothing while agents just work; it lights up only when one needs you. *(AgentNotch)*
7. **Per-session identity.** A stable color or tiny avatar per session, so the collapsed dots tell sessions apart, not just states. Fits the "AI vibe". *(Notchi sprites)*
8. **Hide while sharing your screen or in full-screen video.** Agent messages and commands can be private. *(boring.notch full-screen hide)*
9. **Phone handoff.** Mirror approvals to your phone when you're away. Needs a server or a push service, so it's the biggest step and has privacy costs. *(Pushary Isle, CodeIsland)*
10. **No-notch fallback.** A thin top bar on external displays. *(NotchNook, VibeHub)*

Skip: music, calendar, weather, HUD replacements, AirDrop, clipboard, system monitors. Those are general notch utilities; Ping stays the attention layer for agents.

## Sources
- NotchNook: https://lo.cafe/notchnook, https://setapp.com/apps/notchnook, https://bundlehunt.com/deal/notchnook, https://mezha.ua/en/2024/07/22/the-notchnook-app-has-been-released-for-macbook-which-makes-the-camera-cutout-on-top-of-the-screen-functional/
- boring.notch: https://github.com/TheBoredTeam/boring.notch, https://chatgate.ai/post/boring-notch
- Alcove: https://sourceforge.net/app/alcove/mac/, https://www.slashgear.com/2175261/macos-apps-give-features-apple-doesnt-include/
- DynamicLake Pro: https://thesweetbits.com/tools/dynamiclake-review/, https://www.idownloadblog.com/?p=1021243, https://forums.macrumors.com/threads/i-made-dynamic-island-notifications-with-quick-reply-for-macos.2431579
- Atoll: https://github.com/Ebullioscopic/Atoll, https://mac.softpedia.com/get/Utilities/Atoll.shtml
- NotchDrop / Droppy: https://github.com/Lakr233/NotchDrop, https://www.producthunt.com/posts/droppy-3
- Claude Island / Vibe Notch / forks: https://docsearch.algolia.com/mcp/docs/repo/farouqaldori/vibe-notch, https://awesome.ecosyste.ms/projects/github.com%2F824zzy%2Fclaude-visor, https://github.com/mtunique/VibeHub
- Notchi: https://github.com/sk-ruban/notchi, https://deepwiki.com/sk-ruban/notchi, https://korben.info/en/notchi-pixel-art-mascot-macbook-notch-claude-code.html
- AgentNotch: https://chatgate.ai/post/agentnotch, https://feedbagel.com/post/agentnotch-macos-menu-bar-app-for-real-time-ai-coding-assistant-monitoring
- Agent Island: https://itwire.com/business-it-news/data/agent-island-lets-developers-walk-away-while-claude-code-and-codex-keep-working, https://newreleases.io/project/github/tristan666666/agent-island/release/v1.0.0, https://dev.to/agentis/an-ai-coding-status-companion-should-observe-not-operate-3407
- Pushary Isle: https://pushary.com/docs/agents/mac-app, https://pushary.com/mac-notch-app, https://toolradar.com/tools/pushary
- CodeIsland: https://www.sourcepulse.org/projects/27607032, https://dev.to/krisying/i-turned-my-macbooks-notch-into-a-control-center-for-ai-coding-agents-2o57
- Vibe Island: https://vibeisland.app/claude-code/, https://vibeisland.app/best-ai-agent-notch-apps/ (vendor comparison)
