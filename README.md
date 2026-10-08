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
- **switch** — flip which version is loaded: patched ⇄ original.

**Update Plugins** updates every installed plugin.

Your edits live in a private git repo, so they are easy to track and send
upstream. The original plugin is never modified.

## License

MIT
