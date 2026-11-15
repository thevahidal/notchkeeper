#!/bin/sh
# Phone notifications through ntfy (https://ntfy.sh): install the ntfy app, subscribe to a hard-to-guess topic,
# and set that topic in Settings → Plugins. Only the agent's title and its state leave your Mac.
input=$(cat)
get() { printf %s "$input" | plutil -extract "$1" raw -o - - 2>/dev/null; }
# topic.txt and server.txt are from before plugins had settings; still honored.
topic=$(get settings.topic)
[ -n "$topic" ] || topic=$(cat topic.txt 2>/dev/null)
topic=$(printf %s "$topic" | tr -cd 'A-Za-z0-9_-')
[ -n "$topic" ] || exit 0
server=$(head -1 server.txt 2>/dev/null || get settings.server)
[ -n "$server" ] || server=https://ntfy.sh
title=$(get session.title | head -c 120)
case "$(get event)" in
  needs-you) msg="Needs you"; tag="raised_hand" ;;
  done) msg="Finished"; tag="white_check_mark" ;;
  *) exit 0 ;;
esac
curl -fsS -m 8 -H "Title: $title" -H "Tags: $tag" -d "$msg" "$server/$topic" >/dev/null
