#!/bin/sh
# Asks the Notchkeeper app to approve a tool call, waiting up to 30s.
# No answer, "terminal", or app not running: print nothing, so Claude shows its normal prompt.
reply=$(tr -d '\n' | { cat; echo; } | nc -U -w 30 "$HOME/.notchkeeper/notchkeeper.sock" 2>/dev/null)

case "$reply" in
  allow) printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n' ;;
  deny) printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from Notchkeeper"}}}\n' ;;
  # Notchkeeper sends Claude's own suggested rules, scoped to this session, as one line of JSON.
  "allow-session ["*"]") printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":%s}}}\n' "${reply#allow-session }" ;;
  # Deny and tell Claude why or what to do instead; Notchkeeper sends the message as a JSON string.
  "deny-message \""*"\"") printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":%s}}}\n' "${reply#deny-message }" ;;
esac
exit 0
