// Notchkeeper for OpenCode: turns OpenCode's events into Claude Code-style hook events
// and hands each to notchkeeper-hook.sh, which adds where the agent runs and sends it to the app.
import { spawn } from "node:child_process"

const hook = `${process.env.HOME}/.notchkeeper/hooks/notchkeeper-hook.sh`

export const Notchkeeper = async ({ directory }) => {
  const busy = new Set()
  const roles = new Map()
  const lastText = new Map()

  const send = (sessionID, name, extra = {}) => {
    try {
      const child = spawn(hook, ["opencode"], { stdio: ["pipe", "ignore", "ignore"] })
      child.on("error", () => {})
      child.stdin.on("error", () => {})
      child.stdin.end(JSON.stringify({ session_id: sessionID, hook_event_name: name, cwd: directory, ...extra }))
    } catch {}
  }

  return {
    event: async ({ event }) => {
      const p = event.properties ?? {}
      if (event.type === "message.updated") roles.set(p.info?.id, p.info?.role)
      if (event.type === "message.part.updated" && p.part?.type === "text" && roles.get(p.part.messageID) === "assistant") {
        lastText.set(p.sessionID, p.part.text)
      }
      if (event.type === "session.status") {
        // Busy fires many times per turn; only the change matters.
        const nowBusy = p.status?.type !== "idle"
        if (nowBusy && !busy.has(p.sessionID)) send(p.sessionID, "UserPromptSubmit")
        if (!nowBusy && busy.has(p.sessionID)) send(p.sessionID, "Stop", { last_assistant_message: lastText.get(p.sessionID) ?? "" })
        nowBusy ? busy.add(p.sessionID) : busy.delete(p.sessionID)
      }
      if (event.type === "session.deleted") send(p.info?.id ?? p.sessionID, "SessionEnd")
    },
    "tool.execute.after": async (input) => {
      const args = input.args ?? {}
      // Notchkeeper names files by Claude's file_path.
      send(input.sessionID, "PostToolUse", { tool_name: input.tool, tool_input: { ...args, ...(args.filePath && { file_path: args.filePath }) } })
    },
  }
}
