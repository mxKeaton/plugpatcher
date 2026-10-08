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

### Optional: launch a harness instead of the agent (the **AI** button)

`plugpatcher open <id>` launches your default coding agent. If you prefer to
open a harness of your own, set the `ai` config command:

```bash
plugpatcher config ai "<your-harness-command>"
```

`{dir}` in the command is replaced with the repo path, and the command runs in
the repo. This is unset by default — Omarchy has no "default harness" setting.

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
