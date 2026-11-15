# Notchkeeper protocol

Everything Notchkeeper shows arrives as JSON over one local Unix socket. Anything that can write to that socket can show up in the notch, and anything that speaks it can replace the notch, for example a Linux top-bar client.

## The socket

- Path: `~/.notchkeeper/notchkeeper.sock`. The folder is `700` and the socket `600`: only your user can connect.
- One connection per message: connect, write one line of JSON ending in `\n`, then close your writing side and wait for the app to hang up (like `nc -U`). Messages over 1 MB are dropped.

## Agent events

What the hook scripts send. The body is the agent's own hook JSON (Claude Code, Codex, or Gemini CLI), plus these fields added by `notchkeeper-hook.sh`:

| Field | Meaning |
|---|---|
| `agent` | `""` for Claude Code, else `codex` or `gemini` |
| `tty` | the agent's terminal, e.g. `ttys012`; `??` for none (the desktop app) |
| `term` | `$TERM_PROGRAM` |
| `app` | `$__CFBundleIdentifier`, the macOS app the terminal runs in |
| `tmux_pane`, `tmux_socket` | from `$TMUX_PANE` and `$TMUX` |
| `wezterm_pane` | `$WEZTERM_PANE` |
| `kitty_window`, `kitty_socket` | `$KITTY_WINDOW_ID`, `$KITTY_LISTEN_ON` |

Fields Notchkeeper reads from the agent's JSON: `session_id`, `hook_event_name`, `cwd`, `transcript_path`, `permission_mode`, `tool_name`, `tool_input`, `prompt`, `message`, `notification_type`, `last_assistant_message`, `agent_id`, `agent_type`, `model`, `permission_suggestions`. Gemini's names (`BeforeTool`, `AfterAgent`, `prompt_response`, …) are mapped to Claude's.

## Permission requests

A `PermissionRequest` event keeps the connection open. Notchkeeper answers with one line, then closes:

| Reply | The hook prints |
|---|---|
| `allow` | allow |
| `deny` | deny, message "Denied from Notchkeeper" |
| `allow-session [ …rules… ]` | allow, with Claude's own suggested rules scoped to the session (`updatedPermissions`) |
| `deny-message "…"` | deny, with your message (a JSON string) |
| anything else, or nothing | no decision: the agent shows its normal prompt |

## Items

Post anything, not just agents:

```json
{"hook_event_name": "Item", "session_id": "item:<source>:<id>", "source": "deploy",
 "title": "Deploy to staging", "state": "working", "detail": "Step 3 of 5", "url": "https://…"}
```

- `state`: `working`, `needs-you`, `done`, or `remove`.
- `source`: lowercase letters, digits and `-`, up to 20 characters. It shows as a tag.
- `url`: `http(s)` only; clicking the row opens it.

From the shell, use `~/.notchkeeper/bin/notchkeeper`:

```bash
notchkeeper notify --source deploy --id staging --title "Deploy to staging" --state done --url https://…
notchkeeper run -- npm run build     # working while it runs; done, or needs-you with the exit code
```

## Plugins

A plugin is a folder in `~/.notchkeeper/plugins/` with a `plugin.json`:

```json
{ "name": "Journal", "description": "…", "run": "run.sh", "on": ["needs-you", "done", "approval"] }
```

Turn it on in the menu bar under Plugins. When one of its events happens, Notchkeeper runs `run` (it must be inside the folder and executable; no shell, 10-second limit) with this on stdin:

```json
{ "event": "done",
  "session": { "id": "…", "title": "…", "repo": "…", "agent": "claude", "detail": "…", "url": "" },
  "tool": "Bash", "target": "npm test", "risk": "medium" }
```

`tool`, `target` and `risk` come only with `approval`.

A plugin can declare settings. Each needs a `key` and a `type` (`text`, `toggle` or `choice` with `options`); `title` and `default` are optional, and a plugin should work on its defaults alone:

```json
"settings": [
  { "key": "topic", "title": "Topic", "type": "text" },
  { "key": "voice", "title": "Voice", "type": "choice", "options": ["Samantha", "Daniel"], "default": "Samantha" }
]
```

Your values are kept in `~/.notchkeeper/plugin-settings/<folder>.json` (readable only by you, editable by hand). Every event carries them, defaults filled in, as `"settings": { "topic": "…", "voice": "Samantha" }`. Undeclared keys and invalid values are dropped, and text is capped at 500 characters.

Examples ship in the app: menu bar → Plugins → Add Example Plugins.

## Porting

The hooks and this protocol have nothing Mac-specific in them. The Mac parts are the notch window, AppleScript and terminal jumps, and the sounds. A Linux client could listen on the same socket and draw the same states in a GNOME Shell extension, a Waybar module or a small GTK overlay, reusing the hook scripts unchanged.
