# PlugPatcher

Edit Omarchy shell plugins without giving up updates.

Install a plugin normally. If you later want to change it, PlugPatcher clones it
into a private per-project git repo, generates an edited clone, and makes the
shell load that clone — while the **original install stays untouched and keeps
updating** with the normal Omarchy commands.

```
~/.config/omarchy/plugins/<id>/            original  — untouched, updatable
~/.local/share/plugpatcher/<id>/           repo      — your git repo (source of truth)
~/.config/omarchy/plugins/local.<seg>/     clone     — generated; what the shell loads
```

The clone sets `omarchy.clonedFrom = <id>`, the same convention Omarchy's own
`omarchy plugin clone` uses, so the shell routes calls to the clone, disables the
original, and moves the bar/layout entry automatically. Unlike the built-in
clone (first-party only, no update path), PlugPatcher works for any plugin and
adds `sync` (rebase onto upstream) and `pr` (open a pull request).

## Install

```bash
git clone https://github.com/<you>/PlugPatcher
cd PlugPatcher
./install.sh --enable
```

Installs:
- `~/.local/bin/plugpatcher` — the CLI
- `~/.config/omarchy/plugins/plugpatcher` — the manager bar widget
- `~/.pi/agent/skills/plugpatcher/SKILL.md` — the AI skill

## Use

```bash
plugpatcher list                     # what's installed and what's being edited
plugpatcher setup <plugin-id>        # start editing (original stays installed)
plugpatcher status <plugin-id>       # branch, upstream, ahead/behind
plugpatcher sync <plugin-id>         # pull upstream in (rebase), regenerate the clone
plugpatcher open <plugin-id>         # resume the default coding agent in the repo
plugpatcher pr <plugin-id>           # open a PR for your changes
plugpatcher remove <plugin-id>       # stop editing; restore the original
```

### Settings (the gear button)

The panel's gear opens settings for how the **AI** button opens projects:

- **AI harness** — Omarchy's default agent, a specific installed agent, `herdr`
  / `tmux` if installed, or a custom command. The list only shows what's
  installed on the machine.
- **Model** — passed to the agent (`--model`) where supported.

Stored in `~/.config/plugpatcher/config.json`, also settable with
`plugpatcher config <key> <value>`. `plugpatcher settings` prints the available
harnesses and models as JSON (used to populate the dropdowns).

Edit files in `~/.local/share/plugpatcher/<id>/` (the repo), then
`plugpatcher sync <id>` to regenerate the loaded clone. `sync` only merges when
there is no conflict; on conflict it aborts, changes nothing, and notifies you.

## Why a clone id

Omarchy loads exactly one plugin per id from `~/.config/omarchy/plugins/<id>`, so
the edited version must be a clone with its own id (`local.<last-segment>`).
`clonedFrom` makes that transparent to IPC and to the bar/layout.

## Safety

- Nothing in `/usr/share/omarchy` is touched, so `omarchy update` is unaffected.
- `omarchy update` restarts the shell but does **not** run `omarchy plugin update`.
- Every operation is user-space and reversible: `plugpatcher remove <id>` restores
  the original. The original plugin is never modified.

## License

MIT
