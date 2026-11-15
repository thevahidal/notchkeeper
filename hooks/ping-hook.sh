#!/bin/sh
# Sends the event to the Ping app. Silent and non-blocking when the app isn't running.
# Adds the terminal Claude runs in ("??" for the desktop app), so Ping can jump to it.
# Hooks run detached from the terminal, so walk up to the first ancestor that has one.
pid=$$
tty="??"
while [ "$pid" -gt 1 ] && [ "$tty" = "??" ]; do
  tty=$(ps -o tty= -p "$pid" | tr -d ' ')
  pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
done
# Both go into JSON and a sed replacement, so keep only safe characters.
term=$(printf %s "$TERM_PROGRAM" | tr -cd 'A-Za-z0-9._-')
tty=$(printf %s "$tty" | tr -cd 'A-Za-z0-9?')
extra=$(printf ',"tty":"%s","term":"%s"}' "$tty" "$term")
tr -d '\n' | { cat; echo; } | sed "s|}\$|$extra|" | nc -U -w 1 "$HOME/.ping/ping.sock" >/dev/null 2>&1
exit 0
