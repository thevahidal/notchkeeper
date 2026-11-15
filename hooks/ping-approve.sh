#!/bin/sh
# Asks the Ping app to approve a tool call, waiting up to 30s.
# No answer, "terminal", or app not running: print nothing, so Claude shows its normal prompt.
reply=$(tr -d '\n' | { cat; echo; } | nc -U -w 30 "$HOME/.ping/ping.sock" 2>/dev/null)

case "$reply" in
  allow) printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n' ;;
  deny) printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Ping"}}}\n' ;;
esac
exit 0
