# PlugPatcher

Patch Omarchy shell plugins without losing updates.

Install a plugin normally. When you want to change it, hit **Patch** in the
PlugPatcher panel: your edited version is loaded, while the original install
stays untouched and keeps updating.

## Install

```bash
git clone https://github.com/mxKeaton/plugpatcher
cd plugpatcher
./install.sh --enable
```

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

`plugpatcher adopt <id>` (CLI) brings an existing plugin project — a git repo
that already has your changes — under PlugPatcher, keeping its history.
**Update Plugins** updates every installed plugin.

Your edits live in a private git repo, so they are easy to track and send
upstream. The original plugin is never modified.

## For AI agents

The repo ships an agent skill at `skills/plugpatcher/SKILL.md` that teaches a
coding agent how to work with PlugPatcher (edit in the repo, `sync`, open a PR).
It is not installed automatically — copy it into your agent's skills directory,
e.g. `~/.pi/agent/skills/plugpatcher/` or `~/.claude/skills/plugpatcher/`.

## License

MIT
