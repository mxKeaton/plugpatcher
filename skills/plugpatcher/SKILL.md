---
name: plugpatcher
description: >
  REQUIRED for editing, patching, extending, or fixing any Omarchy shell plugin
  while keeping the original install pristine and updatable. Use when asked to
  customize a plugin, keep local changes across plugin updates, manage an
  adopted/patched plugin, sync upstream changes into a modified plugin, open a
  modified plugin for AI editing, or open a pull request for local plugin
  changes. Triggers: "edit plugin", "patch plugin", "customize plugin X",
  "my changes to plugin X", "adopt plugin", "plugpatcher", "sync plugin",
  "update my patched plugin", "PR my plugin change".
---

# PlugPatcher

PlugPatcher lets a user keep a normally-installed Omarchy plugin **pristine and
updatable** while loading their own edited version. It works for any plugin
(first- or third-party) because Omarchy's built-in `omarchy plugin clone` only
handles first-party (`omarchy.*`) plugins and has no update/merge path.

## The model

```
~/.config/omarchy/plugins/<id>/            original  — untouched, `omarchy plugin update`-able
~/.local/share/plugpatcher/<id>/           repo      — git clone of upstream + your branch (source of truth)
~/.config/omarchy/plugins/local.<seg>/     clone     — generated from the repo; what the shell loads
~/.local/share/plugpatcher/catalog.json    state     — machine-readable list for the GUI/AI
```

The clone carries `omarchy.clonedFrom = <id>`, so the shell:
- routes IPC/service calls aimed at the original id to the clone,
- auto-disables the original when the clone is enabled,
- resolves the bar/layout entry to the clone.

`local.<seg>` is `local.` + the last dotted segment of the id
(`io.github.rk4500.adaptive-bar` → `local.adaptive-bar`).

## Commands (`~/.local/bin/plugpatcher`)

| Command | Effect |
|---|---|
| `plugpatcher list` | installed plugins + edit state (writes `catalog.json`) |
| `plugpatcher status <id>` | repo/branch/upstream ahead-behind for one plugin |
| `plugpatcher setup <id> [url]` | start editing: clone upstream into the repo, generate the clone, switch to it |
| `plugpatcher adopt [id] [--repo PATH] [--branch B] [--upstream URL]` | bring an existing git working copy under PlugPatcher, keeping its history; makes `local` the patched branch and resets the installed original to pristine (no arg = interactive wizard) |
| `plugpatcher sync <id>` | `git fetch` upstream, rebase your branch, regenerate the clone; aborts on conflict |
| `plugpatcher pr <id> [ai|manual]` | push your branch and open a PR: `ai` writes the title/description, `manual` opens GitHub's form (one branch per patch) |
| `plugpatcher pr-cancel <id>` | close the PR most recently opened for `<id>` (also `unpr`) |
| `plugpatcher source <id>` | open the plugin's upstream (source) page in the browser |
| `plugpatcher open-url <url>` | open a URL in the browser |
| `plugpatcher revert <id>` | restore the original, delete/backup the repo |
| `plugpatcher use <id> <side>` | switch the loaded plugin: `patched` or `original` (enable/disable only) |
| `plugpatcher delete <id> <side>` | delete `original`, `patched`, or `both` |
| `plugpatcher open <id>` | launch the configured harness, or the system default agent, in the repo |
| `plugpatcher files <id>` | open the patch folder in the default file manager |
| `plugpatcher editor <id>` | open the patch folder in the default editor |
| `plugpatcher config [k] [v]` | show or set config (`~/.config/plugpatcher/config.json`) |
| `plugpatcher heal` | re-activate adopted clones that went dormant (the panel runs this on refresh) |
| `plugpatcher help` | usage |

## Config

Managed from the panel's gear button, or with `plugpatcher config <key> <value>`.
`~/.config/plugpatcher/config.json`:

- `harness` — what the AI button opens: `herdr`, `tmux`, `terminal`, or `custom`.
  `herdr` opens a Herdr workspace at the repo and starts Omarchy's default agent
  in it; `tmux` / `terminal` open a session at the repo; `custom` runs `command`.
- `command` — used when `harness` is `custom`; `{dir}` expands to the repo path.

`plugpatcher settings` prints the installed harnesses and available models as
JSON (the panel uses it for its dropdowns).

## The workflow an AI should follow

1. **Discover** adopted plugins: read `~/.local/share/plugpatcher/catalog.json`
   or run `plugpatcher list`. A plugin with `state: "editing"` has a repo at
   `~/.local/share/plugpatcher/<id>/`.
2. **To edit**: make changes **in the repo**, not in the loaded clone
   (`plugins/local.<seg>/`). The repo is the source of truth and what `pr` and
   `sync` operate on. If a plugin was already being edited outside PlugPatcher
   (its own git checkout or a fork in `~/Projects`), use `plugpatcher adopt <id>`
   to bring that history in instead of `setup` (which squashes).
3. **After editing**: run `plugpatcher sync <id>` so the loaded clone reflects
   the repo. `sync` regenerates the clone and **restarts the shell** (a plain
   rescan does not reliably rebuild a live widget/panel), so the change becomes
   visible. It is idempotent.
4. **To pull upstream**: `plugpatcher sync <id>`. If upstream changed the same
   lines, `sync` aborts, changes nothing, and notifies; resolve the rebase in
   the repo, then run `sync` again.
5. **To PR**: `plugpatcher pr <id>` (uses `gh`, which Omarchy sets up as the git
   credential helper). Each distinct patch gets its own branch
   (`plugpatcher/<id>-<patch-id>`), so a new round of changes opens a new PR;
   re-running for an unchanged patch just reports the existing PR URL. Close it
   with `plugpatcher pr-cancel <id>`. The `local.<seg>` manifest rewrite never
   enters the PR — it is applied only at clone-generation time.
6. **Never** edit `/usr/share/omarchy`, and never run destructive git commands
   in the original plugin dir. The original remains the updatable baseline.
7. **To stop editing**: `plugpatcher remove <id>` restores the original.

## Notes for agents

- Omarchy's `omarchy plugin update` and `omarchy update` do not understand this
  repo; they act on `plugins/<id>` (the original) only. `omarchy update` just
  restarts the shell and does not touch plugin repos.
- The clone must contain no symlinks (`omarchy-plugin-validate` rejects them);
  generation dereferences any upstream symlinks.
- The GUI version is the `plugpatcher` bar widget (same CLI underneath).
