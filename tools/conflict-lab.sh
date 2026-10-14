#!/usr/bin/env bash
#
# Conflict lab: put a real patched plugin into a real conflict of a chosen kind,
# so the conflict tooling can be exercised by hand in the panel.
#
#   tools/conflict-lab.sh rich    4 files, 3 kinds: two regions in one file,
#                                 add/add, and modify/delete (no text markers)
#   tools/conflict-lab.sh queue   four patch commits; upstream clashes with the
#                                 1st and the 3rd, so resolving reveals another
#   tools/conflict-lab.sh empty   one line, both sides: resolving to upstream
#                                 leaves the patch commit empty (it gets dropped)
#   tools/conflict-lab.sh status  what the lab recorded, and what conflicts now
#   tools/conflict-lab.sh reset   undo everything: patch branch back, upstream
#                                 force-reset, clone rebuilt
#
# A conflict only exists if the upstream really diverged, so this pushes to the
# plugin's upstream (GitHub by default) through its working copy. The live shell
# is never restarted and no notification is sent: PlugPatcher runs with stubbed
# systemd-run / omarchy-shell / omarchy-notification-send on PATH, so the lab
# only touches git repos and PlugPatcher's own files.
#
# Override with: PLUGIN_ID=... UPSTREAM_DIR=... BRANCH=...
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/plugpatcher"

PLUGIN_ID="${PLUGIN_ID:-io.github.mxkeaton.test-omarchy-plugin}"
UPSTREAM_DIR="${UPSTREAM_DIR:-$HOME/Projects/TestOmarchyPlugin}"
BRANCH="${BRANCH:-local}"

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plugpatcher"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/plugpatcher"
REPO_DIR="$DATA_DIR/$PLUGIN_ID"
LAB_DIR="$STATE_DIR/conflict-lab"
STATE="$LAB_DIR/state"
STUBS="$LAB_DIR/stubs"

say()  { printf '\n=== %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'conflict-lab: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- stubs + state

setup_stubs() {
  mkdir -p "$STUBS"
  local s
  for s in systemd-run omarchy-shell omarchy-notification-send; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/$s"
    chmod +x "$STUBS/$s"
  done
}

state_get() { # key
  [[ -f "$STATE" ]] || return 0
  awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$STATE"
}

state_set() { # key value
  mkdir -p "$LAB_DIR"
  local tmp; tmp="$(mktemp "$LAB_DIR/.state.XXXXXX")"
  if [[ -f "$STATE" ]]; then
    awk -F= -v k="$1" '$1 != k' "$STATE" > "$tmp"
  fi
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$STATE"
}

# ------------------------------------------------------------------- primitives

pp() { # run the CLI without touching the live shell
  PATH="$STUBS:$PATH" "$CLI" "$@"
}

require_paths() {
  [[ -d "$REPO_DIR/.git" ]] || die "no patch repo at $REPO_DIR (is $PLUGIN_ID set up?)"
  [[ -d "$UPSTREAM_DIR/.git" ]] || die "no upstream working copy at $UPSTREAM_DIR"
}

require_upstream_clean() {
  if [[ -n "$(git -C "$UPSTREAM_DIR" status --porcelain)" ]]; then
    die "$UPSTREAM_DIR has local changes; commit or stash them first"
  fi
}

require_no_paused() {
  if [[ -d "$REPO_DIR/.git/rebase-merge" || -d "$REPO_DIR/.git/rebase-apply" ]]; then
    die "$PLUGIN_ID already has a paused conflict; run '$0 reset' first"
  fi
}

require_ready() {
  require_paths
  require_upstream_clean
  require_no_paused
  local curb; curb="$(git -C "$UPSTREAM_DIR" rev-parse --abbrev-ref HEAD)"
  [[ "$curb" == "main" ]] || die "$UPSTREAM_DIR is on '$curb', expected main"
  git -C "$UPSTREAM_DIR" fetch -q origin main
  git -C "$UPSTREAM_DIR" merge -q --ff-only origin/main
}

# write into the patch repo / into the upstream working copy
pwrite() { mkdir -p "$REPO_DIR/$(dirname "$1")"; printf '%s' "$2" > "$REPO_DIR/$1"; }
uwrite() { mkdir -p "$UPSTREAM_DIR/$(dirname "$1")"; printf '%s' "$2" > "$UPSTREAM_DIR/$1"; }
uremove() { rm -f "$UPSTREAM_DIR/$1"; }

pcommit() { # message
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm "$1"
}
ucommit_push() { # message
  git -C "$UPSTREAM_DIR" add -A
  git -C "$UPSTREAM_DIR" commit -qm "$1"
  git -C "$UPSTREAM_DIR" push -q origin main
  info "pushed upstream: $1"
}

sync_ok() { # a sync that must succeed
  if ! pp sync "$PLUGIN_ID" >/dev/null 2>&1; then
    die "sync failed when it should not have (see: $CLI sync $PLUGIN_ID)"
  fi
}

sync_conflict() { # a sync that must stop on a conflict
  if pp sync "$PLUGIN_ID" >/dev/null 2>&1; then
    die "sync succeeded, but a conflict was expected"
  fi
  [[ -d "$REPO_DIR/.git/rebase-merge" ]] || die "sync failed without pausing a rebase"
  info "the rebase is paused on a conflict"
}

# ------------------------------------------------------------------- file bodies

one_body() { # line-02 line-10  -> a 12-line file
  local i
  for i in $(seq -w 1 12); do
    case "$i" in
      02) printf '%s\n' "$1" ;;
      10) printf '%s\n' "$2" ;;
      *)  printf 'one-%s\n' "$i" ;;
    esac
  done
}

three_base()   { printf '%s-01\n%s-02\n%s-03\n' "$1" "$1" "$1"; }
three_mine()   { printf '%s-01\n%s-02 (mine)\n%s-03\n' "$1" "$1" "$1"; }
three_theirs() { printf '%s-01\n%s-02 (upstream)\n%s-03\n' "$1" "$1" "$1"; }

# --------------------------------------------------------------------- baseline

lab_baseline() {
  if [[ -z "$(state_get UPSTREAM_PRE)" ]]; then
    state_set UPSTREAM_PRE "$(git -C "$UPSTREAM_DIR" rev-parse main)"
    state_set PATCH_TIP "$(git -C "$REPO_DIR" rev-parse "$BRANCH")"
    info "recorded upstream-pre $(state_get UPSTREAM_PRE)"
    info "recorded patch tip   $(state_get PATCH_TIP)"
  fi
  if [[ -z "$(state_get UPSTREAM_BASE)" ]]; then
    uwrite conflict-lab/one.txt "$(one_body one-02 one-10)"
    uwrite conflict-lab/two.txt "$(three_base two)"
    uwrite conflict-lab/gone.txt "$(three_base gone)"
    uwrite conflict-lab/solo.txt "$(three_base solo)"
    local n
    for n in 1 2 3 4; do uwrite "conflict-lab/f$n.txt" "$(three_base "f$n")"; done
    ucommit_push "conflict lab: baseline files"
    sync_ok
    state_set UPSTREAM_BASE "$(git -C "$UPSTREAM_DIR" rev-parse main)"
    info "baseline recorded: $(state_get UPSTREAM_BASE)"
  fi
}

# ------------------------------------------------------------------ scenarios

scenario_rich() {
  # patch side: two regions in one file, one region in a second file, an added
  # file, and a modified file that upstream deletes.
  pwrite conflict-lab/one.txt "$(one_body 'one-02 (mine)' 'one-10 (mine)')"
  pwrite conflict-lab/two.txt "$(three_mine two)"
  pwrite conflict-lab/gone.txt "$(three_mine gone)"
  pwrite conflict-lab/added.txt "added by my patch
"
  pcommit "conflict lab: patch side (rich)"

  uwrite conflict-lab/one.txt "$(one_body 'one-02 (upstream)' 'one-10 (upstream)')"
  uwrite conflict-lab/two.txt "$(three_theirs two)"
  uremove conflict-lab/gone.txt
  uwrite conflict-lab/added.txt "added upstream
"
  ucommit_push "conflict lab: upstream side (rich)"
}

scenario_queue() {
  local n
  for n in 1 2 3 4; do
    pwrite "conflict-lab/f$n.txt" "$(three_mine "f$n")"
    pcommit "conflict lab: patch commit $n"
  done
  uwrite conflict-lab/f1.txt "$(three_theirs f1)"
  uwrite conflict-lab/f3.txt "$(three_theirs f3)"
  ucommit_push "conflict lab: upstream side (queue)"
}

scenario_empty() {
  pwrite conflict-lab/solo.txt "$(three_mine solo)"
  pcommit "conflict lab: patch side (empty)"
  uwrite conflict-lab/solo.txt "$(three_theirs solo)"
  ucommit_push "conflict lab: upstream side (empty)"
}

# --------------------------------------------------------------------- actions

cmd_status() {
  require_paths
  say "lab state"
  if [[ -f "$STATE" ]]; then sed 's/^/    /' "$STATE"; else info "nothing recorded yet"; fi
  say "patch branch"
  git -C "$REPO_DIR" log --oneline -3 "$BRANCH" | sed 's/^/    /'
  say "conflict now"
  pp conflicts "$PLUGIN_ID" || true
}

cmd_reset() {
  require_paths
  require_upstream_clean
  local pre tip; pre="$(state_get UPSTREAM_PRE)"; tip="$(state_get PATCH_TIP)"
  if [[ -z "$pre" || -z "$tip" ]]; then
    say "nothing to reset"; info "the lab never created a baseline"; return 0
  fi

  say "restoring the upstream"
  git -C "$UPSTREAM_DIR" reset -q --hard "$pre"
  git -C "$UPSTREAM_DIR" push -q --force origin "$pre:main"
  info "upstream main is back at $pre"

  say "restoring the patch branch"
  git -C "$REPO_DIR" rebase --abort >/dev/null 2>&1 || true
  git -C "$REPO_DIR" checkout -q -B "$BRANCH" "$tip"
  git -C "$REPO_DIR" reset -q --hard "$tip"
  git -C "$REPO_DIR" clean -qfd
  info "$BRANCH is back at $tip"

  say "rebuilding the clone"
  sync_ok
  rm -f "$STATE"
  info "lab state cleared"
  pp conflicts "$PLUGIN_ID" || true
}

usage() {
  cat <<'USAGE'
Conflict lab: put a patched plugin into a real conflict to play with.

  tools/conflict-lab.sh rich    4 files, 3 kinds: two regions in one file,
                                add/add, and modify/delete (no text markers)
  tools/conflict-lab.sh queue   four patch commits; upstream clashes with the
                                1st and the 3rd, so resolving reveals another
  tools/conflict-lab.sh empty   one line, both sides: resolving to upstream
                                leaves the patch commit empty (it gets dropped)
  tools/conflict-lab.sh status  what the lab recorded, and what conflicts now
  tools/conflict-lab.sh reset   undo everything: patch branch back, upstream
                                force-reset, clone rebuilt

Env overrides: PLUGIN_ID, UPSTREAM_DIR, BRANCH.
USAGE
}

main() {
  local what="${1:-}"
  case "$what" in
    rich|queue|empty)
      setup_stubs
      require_ready
      lab_baseline
      say "creating the '$what' scenario"
      "scenario_$what"
      sync_conflict
      say "what conflicts now"
      pp conflicts "$PLUGIN_ID" || true
      say "things to try"
      info "plugpatcher conflicts $PLUGIN_ID [--json]"
      info "plugpatcher resolve-hunk $PLUGIN_ID <file> <n> --mine|--upstream|--both"
      info "plugpatcher resolve-file $PLUGIN_ID <file> --mine|--upstream"
      info "plugpatcher skip $PLUGIN_ID      (drop the stuck commit)"
      info "plugpatcher resolve $PLUGIN_ID   (finish once every file is resolved)"
      info "plugpatcher abort $PLUGIN_ID     (give up on the update)"
      info "plugpatcher undo $PLUGIN_ID      (back to before the sync)"
      info "$0 reset                        (undo the whole lab)"
      ;;
    status) setup_stubs; cmd_status ;;
    reset)  setup_stubs; cmd_reset ;;
    ""|-h|--help|help) usage ;;
    *) die "unknown scenario '$what' (try: $0 help)" ;;
  esac
}

main "$@"
