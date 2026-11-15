#!/usr/bin/env python3
"""Builds docs/plugins.json from marketplace/*.json. --check validates without writing."""
import hashlib
import io
import json
import os
import posixpath
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LISTINGS = ROOT / "marketplace"
OUT = ROOT / "docs" / "plugins.json"
EVENTS = {"needs-you", "done", "approval"}
# Official comes from where the code lives, never from a field the author sets.
OFFICIAL_OWNER = "https://github.com/thevahidal/"
FIELDS = {"author", "repo", "commit", "path", "license", "sendsDataOffMac", "builtIn"}


def fail(id, message):
    sys.exit(f"marketplace/{id}.json: {message}")


def files(id, listing):
    """The plugin folder's files as {relative path: (executable, bytes)}."""
    if listing.get("builtIn"):
        folder = ROOT / "plugins" / id
        return {p.relative_to(folder).as_posix(): (os.access(p, os.X_OK), p.read_bytes()) for p in folder.rglob("*") if p.is_file()}
    repo = listing["repo"].removeprefix("https://github.com/")
    url = f"https://codeload.github.com/{repo}/tar.gz/{listing['commit']}"
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            archive = tarfile.open(fileobj=io.BytesIO(response.read()), mode="r:gz")
    except Exception as error:
        fail(id, f"can't download {url}: {error}")
    path = listing.get("path") or ""
    found = {}
    for member in archive.getmembers():
        rest = member.name.partition("/")[2]
        rel = rest[len(path) + 1:] if path and rest.startswith(path + "/") else (rest if not path else "")
        if not rel:
            continue
        if member.issym() or member.islnk():
            fail(id, "the plugin contains symlinks, which aren't allowed")
        if member.isfile():
            found[rel] = (bool(member.mode & 0o111), archive.extractfile(member).read())
    if "plugin.json" not in found:
        fail(id, f"no plugin.json in {path or 'the top folder'} of {repo} at {listing['commit']}")
    return found


def content_hash(found):
    """Same scheme as PluginInstaller.contentHash: one line per file, sorted by path bytes."""
    lines = b"".join(
        f"{path}\0{'x' if executable else '-'}\0{hashlib.sha256(data).hexdigest()}\n".encode()
        for path, (executable, data) in sorted(found.items(), key=lambda item: item[0].encode()))
    return hashlib.sha256(lines).hexdigest()


def check_listing(id, listing):
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", id):
        fail(id, "id must be lowercase letters, digits and dashes")
    if unknown := set(listing) - FIELDS:
        fail(id, f"unknown fields: {', '.join(sorted(unknown))}")
    for key in ("author", "license"):
        if not isinstance(listing.get(key), str) or not 0 < len(listing[key]) <= 60:
            fail(id, f"{key} is required, up to 60 characters")
    if not isinstance(listing.get("sendsDataOffMac"), bool):
        fail(id, "sendsDataOffMac must be true or false")
    if listing.get("builtIn"):
        return
    if not re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+", listing.get("repo", "")):
        fail(id, "repo must be https://github.com/<owner>/<repo>")
    if not re.fullmatch(r"[0-9a-f]{40}", listing.get("commit", "")):
        fail(id, "commit must be a full 40-character sha")
    # The path ends up in a shell command, so only plain folder names are allowed.
    path = listing.get("path", "")
    if not isinstance(path, str) or not re.fullmatch(r"([\w.-]+(/[\w.-]+)*)?", path) or ".." in path.split("/"):
        fail(id, "path must be a folder inside the repo (letters, digits, . _ - and /)")


def check_manifest(id, plugin):
    run = plugin.get("run")
    if not isinstance(run, str) or run.startswith("/") or posixpath.normpath(run).startswith(".."):
        fail(id, "plugin.json: run must be a script inside the plugin's folder")
    name, description = plugin.get("name"), plugin.get("description")
    if not isinstance(name, str) or not 0 < len(name) <= 40 or not isinstance(description, str) or not 0 < len(description) <= 300:
        fail(id, "plugin.json: name (up to 40 characters) and description (up to 300) are required")
    events = plugin.get("on", [])
    if not events or not set(events) <= EVENTS:
        fail(id, f"plugin.json: on must list some of {', '.join(sorted(EVENTS))}")
    for setting in plugin.get("settings", []):
        if not setting.get("key") or setting.get("type") not in ("text", "toggle", "choice"):
            fail(id, "plugin.json: each setting needs a key and a type of text, toggle or choice")
        if setting["type"] == "choice" and not setting.get("options"):
            fail(id, f"plugin.json: choice setting {setting['key']} needs options")


def entry(file):
    id = file.stem
    try:
        listing = json.loads(file.read_text())
    except json.JSONDecodeError as error:
        fail(id, f"not valid JSON: {error}")
    check_listing(id, listing)
    found = files(id, listing)
    try:
        plugin = json.loads(found["plugin.json"][1])
    except (KeyError, json.JSONDecodeError):
        fail(id, "plugin.json is missing or not valid JSON")
    check_manifest(id, plugin)
    builtIn = bool(listing.get("builtIn"))
    result = {
        "id": id, "name": plugin["name"], "description": plugin["description"],
        "author": listing["author"], "license": listing["license"], "builtIn": builtIn,
        "official": builtIn or listing["repo"].startswith(OFFICIAL_OWNER),
        "sendsDataOffMac": listing["sendsDataOffMac"], "events": plugin["on"],
        "settings": [{k: s[k] for k in ("key", "title", "type", "options") if k in s} for s in plugin.get("settings", [])],
        "sha256": content_hash(found),
    }
    if builtIn:
        result |= {"source": f"https://github.com/thevahidal/notchkeeper/tree/main/plugins/{id}", "install": ""}
    else:
        repo, path = listing["repo"].removeprefix("https://github.com/"), listing.get("path") or ""
        result |= {"repo": repo, "commit": listing["commit"], "path": path,
                   "source": f"{listing['repo']}/tree/{listing['commit']}/{path}".rstrip("/"),
                   "install": f"nk plugin install {id}"}
    return result


def main():
    plugins = [entry(file) for file in sorted(LISTINGS.glob("*.json"))]
    plugins.sort(key=lambda p: (not p["official"], not p["builtIn"], p["name"].lower()))
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
