#!/bin/sh
# Sends the event to the Notchkeeper app. Silent and non-blocking when the app isn't running.
# Adds where the agent runs (tty, terminal app, tmux / WezTerm / kitty pane) so Notchkeeper can jump to it,
# and which agent sent it ($1: codex, gemini; none means Claude Code).
# Hooks run detached from the terminal, so walk up to the first ancestor that has one.
pid=$$
tty="??"
while [ "$pid" -gt 1 ] && [ "$tty" = "??" ]; do
  tty=$(ps -o tty= -p "$pid" | tr -d ' ')
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done
# Everything goes into JSON and a sed replacement, so keep only safe characters.
safe() { printf %s "$1" | tr -cd "$2"; }
agent=$(safe "$1" 'a-z')
term=$(safe "$TERM_PROGRAM" 'A-Za-z0-9._-')
app=$(safe "$__CFBundleIdentifier" 'A-Za-z0-9.-')
tty=$(safe "$tty" 'A-Za-z0-9?')
tmux_pane=$(safe "$TMUX_PANE" '%0-9')
tmux_socket=$(safe "${TMUX%%,*}" 'A-Za-z0-9/._-')
wezterm_pane=$(safe "$WEZTERM_PANE" '0-9')
kitty_window=$(safe "$KITTY_WINDOW_ID" '0-9')
kitty_socket=$(safe "$KITTY_LISTEN_ON" 'A-Za-z0-9/:._-')
extra=$(printf ',"tty":"%s","term":"%s","app":"%s","agent":"%s","tmux_pane":"%s","tmux_socket":"%s","wezterm_pane":"%s","kitty_window":"%s","kitty_socket":"%s"}' \
  "$tty" "$term" "$app" "$agent" "$tmux_pane" "$tmux_socket" "$wezterm_pane" "$kitty_window" "$kitty_socket")
tr -d '\n' | { cat; echo; } | sed "s|}\$|$extra|" | nc -U -w 1 "$HOME/.notchkeeper/notchkeeper.sock" >/dev/null 2>&1
# Codex reads a Stop hook's stdout as JSON; an empty object means "carry on".
[ "$agent" = codex ] && echo '{}'
exit 0
