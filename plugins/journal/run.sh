#!/bin/sh
# One line per event in ~/.notchkeeper/journal/YYYY-MM-DD.md, so you can look back at your day.
input=$(cat)
get() { printf %s "$input" | plutil -extract "$1" raw -o - - 2>/dev/null; }
dir="$HOME/.notchkeeper/journal"
mkdir -p "$dir"
file="$dir/$(date +%F).md"
[ -f "$file" ] || printf '# %s\n\n' "$(date '+%A, %B %e')" > "$file"
case "$(get event)" in
  needs-you) mark="needs you" ;;
  done) mark="finished" ;;
  approval) mark="asked to use $(get tool)" ;;
esac
printf -- '- %s **%s** (%s) %s: %s\n' "$(date +%H:%M)" "$(get session.title)" "$(get session.repo)" "$mark" "$(get session.detail | head -c 160)" >> "$file"
