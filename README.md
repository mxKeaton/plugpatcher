# PlugPatcher

Patch Omarchy shell plugins without losing updates.

Install a plugin normally. When you want to change it, hit **Patch** in the
PlugPatcher panel: your edited version is loaded, while the original install
stays untouched and keeps updating.

## Install

```bash
omarchy plugin add https://github.com/mxKeaton/plugpatcher --enable
```

That is the whole setup. The plugin ships the `plugpatcher` command it runs, so
there is nothing else to install. (The CLI is also kept on your `PATH` only if
you use the [manual install](#manual-install-optional).)

## Remove

PlugPatcher manages *other* plugins, so remove it in this order:

```bash
# 1. put every patched plugin back (restores the original, removes your clone)
CLI=~/.config/omarchy/plugins/io.github.mxkeaton.plugpatcher/bin/plugpatcher
"$CLI" list                  # what is being edited
"$CLI" revert <plugin-id>    # repeat for each; --help for the options

# 2. remove the bar widget
omarchy plugin remove io.github.mxkeaton.plugpatcher --yes

# 3. delete PlugPatcher's own data
rm -rf ~/.local/share/plugpatcher ~/.local/state/plugpatcher ~/.config/plugpatcher
```

If you used the manual install, also `rm ~/.local/bin/plugpatcher` and the
`plugpatcher` folder you copied into your agent's skills directory.

### What it touches

Everything is inside your home directory; nothing in `/usr/share/omarchy` is
modified. Steps 1–3 above remove all of it.

| Path | What |
|---|---|
| `~/.local/share/plugpatcher/<id>/` | your git repo for each patched plugin |
| `~/.config/omarchy/plugins/local.<seg>/` | the generated clone the shell loads |
| `~/.local/state/plugpatcher/` | backups, logs, switch lock |
| `~/.config/plugpatcher/` | settings (which agent the AI button opens) |

## Requirements

- Omarchy (the Quickshell shell)
- `git`, `jq`, `python3`
- `gh` (GitHub CLI) — only for **Send PR** / **Cancel PR**
- `systemd` (`systemd-run`) — used to restart the shell when switching bar widgets

## Use

Open the **PlugPatcher** widget in the bar. Each plugin is a card with the
actions that apply to it:

- **Patch** — start editing a plugin.
- **AI** — open your coding agent in the plugin's code.
- **Editor** / **Browse** — open the code in your editor / file manager.
- **Update** — pull in upstream changes and rebuild your version.
- **Source** — open the plugin's original GitHub page.
- **Send PR** — then pick **Manual PR** (opens GitHub's form for you to fill in) or **AI PR** (writes the title and description for you); **Cancel PR** withdraws it.
- **Delete** — remove the original, the patched copy, or both.
- **switch** — flip which version is loaded: patched ⇄ original (for bar widgets this restarts the shell, ~3–4 s).

`plugpatcher adopt <id>` brings an existing plugin project — a git repo that
already has your changes — under PlugPatcher, keeping its history.
**Update Plugins** updates every installed plugin.

Your edits live in a git repo, so they are easy to track and send upstream. The
original plugin is never modified.

## Manual install (optional)

Only needed if you want `plugpatcher` in your terminal; the panel does not use
it.

```bash
git clone https://github.com/mxKeaton/plugpatcher
cd plugpatcher
./install.sh --enable
```

`./install.sh` installs `~/.local/bin/plugpatcher` and the bar widget; the AI
agent skill is separate (below).

## For AI agents

The repo ships an agent skill at `skills/plugpatcher/SKILL.md` that teaches a
coding agent how to work with PlugPatcher (edit in the repo, `sync`, open a PR).
It is not installed automatically — copy it into your agent's skills directory,
e.g. `~/.pi/agent/skills/plugpatcher/` or `~/.claude/skills/plugpatcher/`.

## License

MIT — see [LICENSE](LICENSE).
