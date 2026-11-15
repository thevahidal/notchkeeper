#!/bin/sh
# Reads the event Notchkeeper sends on stdin and speaks it.
input=$(cat)
get() { printf %s "$input" | plutil -extract "$1" raw -o - - 2>/dev/null; }
title=$(get session.title)
case "$(get event)" in
  needs-you) line="$title needs you" ;;
  done) line="$title is done" ;;
  *) exit 0 ;;
esac
voice=$(get settings.voice)
# A voice that isn't installed falls back to the system one.
[ "$voice" != System ] && [ -n "$voice" ] && say -v "$voice" "$line" 2>/dev/null || say "$line"
