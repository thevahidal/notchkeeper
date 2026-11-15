# Publishing a plugin

The plugin list on the website is built from the files in this folder, one per plugin. Your code stays in your own GitHub repo. A listing points to **one exact commit**, so people install the code that was reviewed.

## Add your plugin

1. Make a plugin: a folder with a `plugin.json` and a script. See [Extend it](../README.md#extend-it) and the [examples](../plugins).
2. Push it to a public GitHub repo.
3. Open a PR here that adds `marketplace/<id>.json`. The `id` is the folder name people install it as: lowercase letters, digits and dashes.

```json
{
  "author": "your-github-name",
  "repo": "https://github.com/you/nk-slack",
  "commit": "full 40-character commit sha",
  "path": "",
  "license": "MIT",
  "sendsDataOffMac": true
}
```

- `path`: the plugin's folder inside the repo, using only letters, digits, `.`, `_`, `-` and `/`. Leave it empty if `plugin.json` is at the top.
- Limits: `author` and `license` up to 60 characters; in `plugin.json`, `name` up to 40 and `description` up to 300. The site shows all text as plain text, never as HTML.
- `sendsDataOffMac`: `true` if the plugin sends anything over the network. Be honest; the site shows it on the card.
- Name, description, events and settings come from your `plugin.json`, so they can't drift from the real plugin.

People install it with `nk plugin install <id>`.

## Updating

Open a PR that changes `commit`. The reviewer reads the changes between the old and new commit. Once it's merged, `nk plugin update <id>` picks it up.

## Checksums

When the list is built, every listed plugin's files are hashed at its commit, and the hash goes into `docs/plugins.json`. `nk plugin install` hashes what it downloads and refuses to install if the two differ. Force-pushing can't change a commit, but it can delete one: then installs fail rather than fetch something else.

Official means the code lives under `github.com/thevahidal`. Everything else is listed as community.

## Review

Checks run on every PR, and a person reads the code before merging. A listing can be removed if the plugin turns out to do something it doesn't say.

## Building the list

```bash
python3 tools/marketplace.py          # writes docs/plugins.json
python3 tools/marketplace.py --check  # fails if a listing is invalid or docs/plugins.json is out of date
```
