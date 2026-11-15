#!/usr/bin/env python3
"""Builds docs/plugins.json from marketplace/*.json. --check validates without writing."""
import json
import posixpath
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LISTINGS = ROOT / "marketplace"
OUT = ROOT / "docs" / "plugins.json"
EVENTS = {"needs-you", "done", "approval"}
FIELDS = {"author", "repo", "commit", "path", "license", "sendsDataOffMac", "builtIn"}


def fail(id, message):
    sys.exit(f"marketplace/{id}.json: {message}")


def manifest(id, listing):
    if listing.get("builtIn"):
        return json.loads((ROOT / "plugins" / id / "plugin.json").read_text())
    repo = listing["repo"].removeprefix("https://github.com/")
    path = posixpath.join(listing.get("path") or "", "plugin.json")
    url = f"https://raw.githubusercontent.com/{repo}/{listing['commit']}/{path}"
    try:
        with urllib.request.urlopen(url, timeout=20) as response:
            return json.loads(response.read())
    except Exception as error:
        fail(id, f"can't read {url}: {error}")


def check_listing(id, listing):
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", id):
        fail(id, "id must be lowercase letters, digits and dashes")
    if unknown := set(listing) - FIELDS:
        fail(id, f"unknown fields: {', '.join(sorted(unknown))}")
    for key in ("author", "license"):
        if not isinstance(listing.get(key), str) or not listing[key]:
            fail(id, f"{key} is required")
    if not isinstance(listing.get("sendsDataOffMac"), bool):
        fail(id, "sendsDataOffMac must be true or false")
    if listing.get("builtIn"):
        return
    if not re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+", listing.get("repo", "")):
        fail(id, "repo must be https://github.com/<owner>/<repo>")
    if not re.fullmatch(r"[0-9a-f]{40}", listing.get("commit", "")):
        fail(id, "commit must be a full 40-character sha")
    path = listing.get("path", "")
    if not isinstance(path, str) or path.startswith("/") or ".." in path.split("/"):
        fail(id, "path must be a folder inside the repo")


def check_manifest(id, plugin):
    run = plugin.get("run")
    if not isinstance(run, str) or run.startswith("/") or posixpath.normpath(run).startswith(".."):
        fail(id, "plugin.json: run must be a script inside the plugin's folder")
    if not isinstance(plugin.get("name"), str) or not isinstance(plugin.get("description"), str):
        fail(id, "plugin.json: name and description are required")
    events = plugin.get("on", [])
    if not events or not set(events) <= EVENTS:
        fail(id, f"plugin.json: on must list some of {', '.join(sorted(EVENTS))}")
    for setting in plugin.get("settings", []):
        if not setting.get("key") or setting.get("type") not in ("text", "toggle", "choice"):
            fail(id, "plugin.json: each setting needs a key and a type of text, toggle or choice")
        if setting["type"] == "choice" and not setting.get("options"):
            fail(id, f"plugin.json: choice setting {setting['key']} needs options")


def install_command(id, listing):
    if listing.get("builtIn"):
        return ""
    folder = posixpath.join('"$d"', listing.get("path") or "")
    return (f'd=$(mktemp -d) && git clone -q {listing["repo"]} "$d" && git -C "$d" checkout -q {listing["commit"]}'
            f' && mkdir -p ~/.notchkeeper/plugins && cp -R {folder.rstrip("/")} ~/.notchkeeper/plugins/{id}')


def entry(file):
    id = file.stem
    try:
        listing = json.loads(file.read_text())
    except json.JSONDecodeError as error:
        fail(id, f"not valid JSON: {error}")
    check_listing(id, listing)
    plugin = manifest(id, listing)
    check_manifest(id, plugin)
    builtIn = bool(listing.get("builtIn"))
    source = (f"https://github.com/thevahidal/notchkeeper/tree/main/plugins/{id}" if builtIn else
              f"{listing['repo']}/tree/{listing['commit']}/{listing.get('path') or ''}".rstrip("/"))
    return {
        "id": id, "name": plugin["name"], "description": plugin["description"],
        "author": listing["author"], "license": listing["license"], "builtIn": builtIn,
        "sendsDataOffMac": listing["sendsDataOffMac"], "events": plugin["on"],
        "settings": [{k: s[k] for k in ("key", "title", "type", "options") if k in s} for s in plugin.get("settings", [])],
        "source": source, "install": install_command(id, listing),
    }


def main():
    plugins = [entry(file) for file in sorted(LISTINGS.glob("*.json"))]
    plugins.sort(key=lambda p: (not p["builtIn"], p["name"].lower()))
    text = json.dumps(plugins, indent=2) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            sys.exit("docs/plugins.json is out of date: run python3 tools/marketplace.py")
        print(f"{len(plugins)} listings OK")
    else:
        OUT.write_text(text)
        print(f"wrote {len(plugins)} plugins to docs/plugins.json")


if __name__ == "__main__":
    main()
