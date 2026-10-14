# Conflicts: design

Goal: a user updates the pristine plugin (or the upstream moves), PlugPatcher notices,
and when the update collides with the user's own patch the user is told **exactly** what
collides and can resolve it **piece by piece** — then finish, drop, or undo.

## Where we are

`sync_repo` fetches and rebases. On a real conflict it leaves the rebase **paused**,
records `{at, upstream, files[]}` in the plugin metadata, notifies, and leaves the loaded
clone at its last good version. The panel shows a danger badge and a box with the
**file names**, and offers `Resolve` (lazygit), `Edit files`, `Continue`, `Abort`.

Missing: the conflicting *content*, per-file / per-hunk resolution, `skip`, a pre-sync
snapshot, and any awareness of the installed checkout as the base.

## Increments

### 1. Say exactly what conflicts
- `plugpatcher conflicts [<id>] [--json]` parses the markers git left in the worktree
  (independent of git) and reports, per file, per conflict: line range, the upstream
  block, the patch block, both labels, plus how many commits are still queued.
- `--json` is the same data for the panel: `{id, paused, onto, remaining, applied, files:[{path, hunks:[{n,start,end,oursLabel,theirsLabel,ours[],theirs[]}]}]}`.
- Every report ends with the exact command that resolves that hunk.
- `status` / `list` gain a `conflict:` line (previously proposed, not built).

### 2. Resolve individually
One place maps the user's words onto git's, because inside a rebase `--ours` is the
**upstream** side and `--theirs` is **your** commit — the opposite of what they suggest.

| user word | git flag |
|---|---|
| `--mine` | `git checkout --theirs` |
| `--upstream` | `git checkout --ours` |

- `plugpatcher resolve-file <id> <file> --mine|--upstream` — whole file, marks it resolved.
- `plugpatcher resolve-hunk <id> <file> <n> --mine|--upstream|--both` — rewrites just that
  marker block (pure text edit, so it works on a file with several conflict regions);
  marks the file resolved once no markers remain.
- `plugpatcher skip <id>` — drop the stuck commit and carry on. The dropped commit is kept
  as `refs/plugpatcher/skipped/<sha>`; the command prints the ref.
- lazygit stays the escape hatch for anything else.

### 3. Never lose work
- `sync_repo` parks `refs/plugpatcher/pre-sync/<ts>` on the patch branch before rebasing
  and records it as `lastBackup`.
- `plugpatcher undo <id>` aborts any paused rebase, keeps the state it replaces as
  `refs/plugpatcher/undo/<ts>`, resets the branch to the snapshot, and rebuilds the clone.
- `rerere` (reuse recorded resolution) enabled on the per-plugin repo, so a conflict you
  resolved once resolves itself the next time upstream touches the same lines.

### 4. Base on what is installed
The plugin directory is already a git checkout on the upstream branch, so its HEAD is
"What is actually installed". Read it, and rebase **from it** when it is ahead of the
patch base — no network, and guaranteed to match the running code. Fall back to fetching
the remote (and say which was used) when the installed copy is not ahead.

### 5. Panel
- Conflict box: one row per file with the conflict count, an inline preview of the first
  conflict (upstream above, yours below), and per-file `Mine / Upstream / Edit`.
- `Skip` and `Undo` actions; conflict line in the catalog (`catalog.json`).

## Testing it by hand

A conflict only exists if the upstream really diverged, so it takes a push to
reproduce. `tools/conflict-lab.sh` does that on the test plugin and leaves the
rebase paused:

```
tools/conflict-lab.sh rich     # 4 files, 3 kinds: two regions in one file,
                               # add/add, and modify/delete (no text markers)
tools/conflict-lab.sh queue    # four patch commits; upstream clashes with the
                               # 1st and the 3rd, so resolving reveals another
tools/conflict-lab.sh empty    # both sides changed one line, so resolving to
                               # upstream leaves the commit empty (it gets dropped)
tools/conflict-lab.sh status   # what the lab recorded, and what conflicts now
tools/conflict-lab.sh reset    # undo the whole lab
```

It records the pre-lab upstream commit and patch tip in
`~/.local/state/plugpatcher/conflict-lab/state`, and never restarts the shell or
sends a notification (stubbed `systemd-run` / `omarchy-shell` /
`omarchy-notification-send` on PATH), so it only touches git repos and
PlugPatcher's own files.

## Not doing

- **Pre-flight prediction** (`merge-tree` / scratch worktree). The pause-and-record path is
  already non-destructive, and a prediction can disagree with the real rebase.
- **`rebase --quit`** — strands a detached HEAD with no good button for that state.
