#!/bin/sh
# Reads the event Notchkeeper sends on stdin and speaks it.
input=$(cat)
event=$(printf %s "$input" | plutil -extract event raw -o - -)
title=$(printf %s "$input" | plutil -extract session.title raw -o - -)
case "$event" in
  needs-you) say "$title needs you" ;;
  done) say "$title is done" ;;
esac
