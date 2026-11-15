#!/bin/sh
# Phone notifications through ntfy (https://ntfy.sh): install the ntfy app, subscribe to a hard-to-guess topic,
# and put that topic in topic.txt next to this script. Only the agent's title and its state leave your Mac.
# Self-hosting ntfy? Put your server's URL in server.txt (default https://ntfy.sh).
[ -f topic.txt ] || exit 0
topic=$(tr -cd 'A-Za-z0-9_-' < topic.txt)
[ -n "$topic" ] || exit 0
server=$(head -1 server.txt 2>/dev/null || echo https://ntfy.sh)
input=$(cat)
event=$(printf %s "$input" | plutil -extract event raw -o - -)
title=$(printf %s "$input" | plutil -extract session.title raw -o - - | head -c 120)
case "$event" in
  needs-you) msg="Needs you"; tag="raised_hand" ;;
  done) msg="Finished"; tag="white_check_mark" ;;
  *) exit 0 ;;
esac
curl -fsS -m 8 -H "Title: $title" -H "Tags: $tag" -d "$msg" "$server/$topic" >/dev/null
