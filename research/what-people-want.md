# Do people want agent dashboards?

Researched 2026-11-15. Follow-up to [agent-dashboards.md](agent-dashboards.md) and [notch-apps.md](notch-apps.md). Sources are mostly launch threads, vendor blogs and GitHub issues; independent reviews are rare, so read this as signal, not proof.

## What the evidence says
- **The pain is real and specific: "which agent is waiting on me?"** Launch threads for notch monitors keep returning to one complaint: you tab into a session and find it has waited ten minutes on a y/n. Commenters ask for a distinct *blocked on you* state, separate from *busy*. A Claude Code issue asks for a floating notification centre that collects permission requests, questions and finished tasks from every session.
- **Anthropic built the same idea into Claude Code.** `claude agents` (Agent View, research preview since May 2026) lists sessions as active, waiting for feedback, completed and so on. That confirms the need. It also means a plain session list is now table stakes. Its gaps: you have to keep that view open, and it lives in one terminal.
- **The market is crowded but shallow.** There are more than a dozen notch apps (Vibe Island, AgentPeek, Chimlo, CodeIsland, Claude Island and others). Paid ones sell at $9–20. Their own pages compete on the same short list: approvals in the notch, jump to the exact tab, plan review, sounds.
- **Big orchestrators (Conductor, Paradev, Vibe Kanban) solve a different job.** They run agents in worktrees. People who already run agents their own way (terminals, desktop app) want an attention layer, not a new home.
- **Skepticism exists.** Coverage of Agent View notes that more visibility doesn't fix trust in what agents do. Approval UX has to make the right call *easier and safer*, not just faster.
- **Asked for, but not core:** combined token or usage totals across sessions; phone handoff.

## What it means for Ping
Ping's niche holds: a glanceable attention layer across terminals and the desktop app, with no window to keep open. What makes it win is answering "who needs me, for how long, and can I fix it from here?" with zero clicks.

What we built from this, in priority order:
1. **Name the agent that needs you** in the collapsed notch, instead of a count.
2. **How long it has waited** on every row ("waiting 4m"), so the longest-blocked agent stands out.
3. **Allow for session**, scoped narrowly: Claude's own suggested rule, this session only, never written to settings.
4. **Sounds that only fire when it matters**, silent for the tab you're looking at, plus a reminder when you've stepped away.
5. **Quiet mode** for people who find a constantly lit notch noisy.
6. **Jump and reply in more terminals** (iTerm2, Terminal.app), since most people aren't on Ghostty.
7. **Plan card**, read-only. Claude ignores a hook's approval for plans, so Ping shows the plan and takes you to approve it, rather than offering a button that wouldn't work.

### Second round (same day): working *better* with agents
Signals: prompt queueing is one of the most-requested missing features (a Claude Code issue for queue mode has 39 comments); parallel agents in git worktrees is the most-recommended workflow; people steer agents constantly; usage limits are a top worry.

Built: start a background agent from the notch (`claude --bg`, optional worktree), background agents tagged and attachable, a per-agent follow-up queue, and "Tell Claude" (deny with a message). Usage limits skipped: only the statusline input or the account token exposes them.

Skipped on purpose: usage and cost dashboards, worktree management, kanban views. They pull Ping toward being an orchestrator.

## Sources
- Notch-app launch threads: https://www.producthunt.com/posts/notchcode, https://www.producthunt.com/posts/agentpeek-2, https://www.producthunt.com/products/agent-notch/makers, https://www.indiehackers.com/product/crewtower
- Product Hunt discussion: https://www.producthunt.com/p/vibecoding/your-ai-agent-is-waiting-for-you-your-attention-isn-t-how-much-time-do-you-lose-to-this
- Feature request: https://claudeissues.com/issue/70591-feature-centralized-permission-approval-notifications-for-multi-agent-workflows
- Agent View: https://claude.com/resources/articles/agent-view-in-claude-code, https://www.buildfastwithai.com/blogs/claude-code-agent-view-guide, https://thenewstack.io/?p=22823177
- Permission hooks: https://claudeissues.com/issue/91216-bug-permissionrequest-hook-permission-suggestions-does-not-match-the-rows-the-pe, https://claudeissues.com/issue/74256-bug-permissionrequest-hook-allow-for-exitplanmode-is-ignored-since-v2-1-199-plan
- Vibe Island: https://vibeisland.app/claude-code/, https://vibecoding.app/blog/vibe-island-review
