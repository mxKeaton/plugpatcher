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
| `plugpatcher sync <id>` | `git fetch` upstream, rebase your branch, regenerate the clone; aborts on conflict |
| `plugpatcher pr <id>` | fork if needed, push your branch, open a PR against upstream |
| `plugpatcher remove <id>` | restore the original, delete/backup the repo |
| `plugpatcher open <id>` | launch the configured harness, or the system default agent, in the repo |
| `plugpatcher files <id>` | open the patch folder in the default file manager |
| `plugpatcher editor <id>` | open the patch folder in the default editor |
| `plugpatcher config [k] [v]` | show or set config (`~/.config/plugpatcher/config.json`) |
| `plugpatcher help` | usage |

## Config

Managed from the panel's gear button, or with `plugpatcher config <key> <value>`.
`~/.config/plugpatcher/config.json`:

- `harness` — what the AI button opens. `default` uses Omarchy's default agent;
  an agent id (`pi`, `claude`, `codex`, `opencode`, …) launches that agent;
  `herdr` / `tmux` open that session; `custom` runs `command`.
- `model` — optional model passed to the agent (`--model`) where supported.
- `command` — used when `harness` is `custom`; `{dir}` expands to the repo path.

`plugpatcher settings` prints the installed harnesses and available models as
JSON (the panel uses it for its dropdowns).

## The workflow an AI should follow

1. **Discover** adopted plugins: read `~/.local/share/plugpatcher/catalog.json`
   or run `plugpatcher list`. A plugin with `state: "editing"` has a repo at
   `~/.local/share/plugpatcher/<id>/`.
2. **To edit**: make changes **in the repo**, not in the loaded clone
   (`plugins/local.<seg>/`). The repo is the source of truth and what `pr` and
   `sync` operate on.
3. **After editing**: run `plugpatcher sync <id>` (or regenerate with
   `setup`-time generation) so the loaded clone reflects the repo, then the
   shell reloads. If a change only needs regenerating without an upstream
   fetch, re-run the generation by calling `sync` (it is idempotent).
4. **To pull upstream**: `plugpatcher sync <id>`. If upstream changed the same
   lines, `sync` aborts, changes nothing, and notifies; resolve the rebase in
   the repo, then run `sync` again.
5. **To PR**: `plugpatcher pr <id>` (uses `gh`, which Omarchy sets up as the git
   credential helper). The `local.<seg>` manifest rewrite never enters the PR —
   it is applied only at clone-generation time.
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
