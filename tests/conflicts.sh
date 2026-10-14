#!/usr/bin/env bash
# Isolated tests for the conflict inspection and per-file/per-hunk resolution.
# Throwaway HOME, stub omarchy commands, nothing real is touched.
#
# Each round gets its own plugin (own upstream, own patch repo) so that one
# round's leftover patch commits cannot interfere with the next one.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export PATH="$T/stubs:$PATH"
mkdir -p "$HOME/.config/omarchy/plugins" "$T/stubs"

pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

CLI="$REPO/bin/plugpatcher"
run() { "$CLI" "$@"; }

# ---- stubs ----
mkstub() { cat > "$T/stubs/$1"; chmod +x "$T/stubs/$1"; }
for s in omarchy omarchy-shell systemd-run omarchy-notification-send; do
  mkstub "$s" <<'EOF'
#!/usr/bin/env bash
if [[ "$(basename "$0")" == omarchy ]]; then printf 'omarchy %s\n' "$*" >> "$HOME/.omarchy-calls"; fi
exit 0
EOF
done
mkstub omarchy-default-agent <<'EOF'
#!/usr/bin/env bash
echo pi
EOF
mkstub omarchy-plugin-list <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--json" ]]; then
  for m in "$HOME"/.config/omarchy/plugins/*/manifest.json; do
    [[ -f "$m" ]] || continue
    printf '%s\n' "$(jq -c '{id:.id}' "$m")"
  done | jq -s '.'
else
  echo "stub list"
fi
EOF
mkstub omarchy-plugin-catalog <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF

# ---- one fresh plugin per round -------------------------------------------
# make_plugin <id> <initial Panel.qml content>: builds an upstream, "installs" it,
# and sets up PlugPatcher for it. Sets ID/SLUG/PREPO/PCLONE/SEED.
make_plugin() { # id content
  ID="$1"; SLUG="${1##*.}"
  PREPO="$HOME/.local/share/plugpatcher/$ID"
  PCLONE="$HOME/.config/omarchy/plugins/local.$SLUG"
  SEED="$T/seed-$SLUG"
  UPSTREAM="$T/up-$SLUG.git"

  git init -q --bare "$UPSTREAM"
  git init -q "$SEED"
  git -C "$SEED" config user.email t@t
  git -C "$SEED" config user.name t
  printf '{"schemaVersion":1,"id":"%s","name":"Test %s","version":"1.0.0","kinds":["panel"],"entryPoints":{"panel":"Panel.qml"}}\n' \
    "$ID" "$SLUG" > "$SEED/manifest.json"
  printf '%b' "$2" > "$SEED/Panel.qml"
  git -C "$SEED" add -A && git -C "$SEED" commit -qm init
  git -C "$SEED" branch -M master
  git -C "$SEED" remote add origin "$UPSTREAM"
  git -C "$SEED" push -q origin master
  git clone -q "$UPSTREAM" "$HOME/.config/omarchy/plugins/$ID"
  run setup "$ID" >/dev/null 2>&1 || fail "setup failed for $ID"
  [[ -f "$PREPO/manifest.json" ]] || fail "patch repo missing for $ID"
}

# patch repo / upstream edits
pw() { printf '%b' "$2" > "$PREPO/$1"; }   # write in the patch repo
pc() {                                      # commit in the patch repo
  git -C "$PREPO" add -A
  git -C "$PREPO" -c user.email=t@t -c user.name=t commit -qm "$1"
}
uw() { printf '%b' "$2" > "$SEED/$1"; }     # write in the upstream
up() {                                      # commit + push upstream
  git -C "$SEED" add -A
  git -C "$SEED" commit -qm "$1"
  git -C "$SEED" push -q origin master
}
sync_conflict() { # sync must fail and leave a paused rebase
  if run sync "$ID" >/dev/null 2>&1; then fail "sync should have reported a conflict"; fi
  [[ -d "$PREPO/.git/rebase-merge" ]] || fail "the conflict did not pause the rebase"
}
mctx() { git -C "$PREPO" diff --name-only --diff-filter=U; }
conflict_field() { jq -r "$1" "$HOME/.local/share/plugpatcher/$ID.json"; }

echo "== setup =="
make_plugin test.report 'l01\nl02\nl03\nl04\nl05\nl06\nl07\nl08\nl09\nl10\nl11\nl12\n'
pass "setup"

echo "== a conflict is described exactly =="
# The patch touches lines 2 and 12; upstream changes the same two lines, far
# enough apart that git reports two separate conflict regions.
pw Panel.qml 'l01\nl02 (mine)\nl03\nl04\nl05\nl06\nl07\nl08\nl09\nl10\nl11\nl12 (mine)\n'
pc "local: change two lines"
uw Panel.qml 'l01\nl02 (upstream)\nl03\nl04\nl05\nl06\nl07\nl08\nl09\nl10\nl11\nl12 (upstream)\n'
up "upstream: change the same two lines"
sync_conflict

json="$(run conflicts "$ID" --json)"
[[ "$(jq -r '.id' <<<"$json")" == "$ID" ]] || fail "json: wrong id"
[[ "$(jq -r '.paused' <<<"$json")" == "true" ]] || fail "json: paused not true"
[[ "$(jq -r '.files | length' <<<"$json")" == "1" ]] || fail "json: expected one conflicted file"
[[ "$(jq -r '.files[0].path' <<<"$json")" == "Panel.qml" ]] || fail "json: wrong file"
[[ "$(jq -r '.files[0].hunks | length' <<<"$json")" == "2" ]] || fail "json: expected two conflict regions"
[[ "$(jq -r '.files[0].hunks[0].ours | join(",")' <<<"$json")" == "l02 (upstream)" ]] \
  || fail "json: the upstream side of region 1 is wrong"
[[ "$(jq -r '.files[0].hunks[0].theirs | join(",")' <<<"$json")" == "l02 (mine)" ]] \
  || fail "json: the patch side of region 1 is wrong"
[[ "$(jq -r '.files[0].hunks[0].start < .files[0].hunks[1].start' <<<"$json")" == "true" ]] \
  || fail "json: conflict regions are out of order"
[[ "$(jq -r '.files[0].hunks[1].ours | join(",")' <<<"$json")" == "l12 (upstream)" ]] \
  || fail "json: the upstream side of region 2 is wrong"
pass "conflicts --json reports the file, both regions, and both sides"

human="$(run conflicts "$ID")"
grep -q "conflict #1" <<<"$human" || fail "human: no conflict #1"
grep -q "conflict #2" <<<"$human" || fail "human: no conflict #2"
grep -q "l02 (upstream)" <<<"$human" || fail "human: the upstream side is missing"
grep -q "l02 (mine)" <<<"$human" || fail "human: the patch side is missing"
grep -q "resolve-hunk $ID Panel.qml 1 --upstream" <<<"$human" || fail "human: no per-region command"
grep -q "1 conflicted file(s)" <<<"$human" || fail "human: file count missing"
pass "conflicts prints both sides with line numbers and the exact commands"

status="$(run status "$ID" 2>/dev/null || true)"
grep -q "^conflict: 1 file(s), 2 region(s)" <<<"$status" || fail "status does not report the conflict"
grep -q "conflict: 1 file(s)" <<<"$(run list 2>/dev/null || true)" || fail "list does not flag the conflict"
pass "status and list report the conflict"

echo "== resolve-hunk: a bad number refuses, a good one rewrites =="
before="$(cat "$PREPO/Panel.qml")"
if run resolve-hunk "$ID" Panel.qml 9 --mine >/dev/null 2>&1; then fail "region 9 should not exist"; fi
[[ "$(cat "$PREPO/Panel.qml")" == "$before" ]] || fail "a bad region number changed the file"
pass "an out-of-range region number leaves the file untouched"

run resolve-hunk "$ID" Panel.qml 1 --mine >/dev/null 2>&1 || fail "resolve-hunk --mine failed"
[[ "$(grep -c '^<<<<<<<' "$PREPO/Panel.qml")" == "1" ]] || fail "one region should remain"
grep -qx 'l02 (mine)' "$PREPO/Panel.qml" || fail "region 1 was not resolved to mine"
if grep -q 'l02 (upstream)' "$PREPO/Panel.qml"; then fail "the upstream side of region 1 is still there"; fi
grep -q 'l12 (upstream)' "$PREPO/Panel.qml" || fail "the untouched region should still show both sides"
[[ "$(mctx)" == "Panel.qml" ]] || fail "the file should still be unmerged"
pass "resolve-hunk --mine rewrites one region and leaves the file unmerged"

# Regions are numbered from the top of the file, so the survivor is #1 again.
run resolve-hunk "$ID" Panel.qml 1 --upstream >/dev/null 2>&1 || fail "resolve-hunk --upstream failed"
grep -qx 'l12 (upstream)' "$PREPO/Panel.qml" || fail "region 2 did not keep upstream"
if grep -q 'l12 (mine)' "$PREPO/Panel.qml"; then fail "the patch side of region 2 is still there"; fi
if grep -q '<<<<<<<' "$PREPO/Panel.qml"; then fail "conflict markers should be gone"; fi
[[ -z "$(mctx)" ]] || fail "the file should be marked resolved"
pass "the regions renumber, and the last one marks the file resolved"

echo "== resolve: finish the rebase and rebuild the clone =="
run resolve "$ID" >/dev/null 2>&1 || fail "resolve failed"
[[ -d "$PREPO/.git/rebase-merge" ]] && fail "the rebase is still paused"
[[ "$(conflict_field '.conflict // "none"')" == "none" ]] || fail "the conflict record was not cleared"
grep -q "l02 (mine)" "$PCLONE/Panel.qml" || fail "the clone is missing the patched side"
grep -q "l12 (upstream)" "$PCLONE/Panel.qml" || fail "the clone is missing the upstream side"
[[ "$(git -C "$PREPO" rev-list --count origin/master..local)" == "1" ]] \
  || fail "the patch branch should be one commit ahead"
pass "resolve finished the rebase and rebuilt the clone"

echo "== resolve-file: take a whole file's side (and drop the empty commit) =="
make_plugin test.file 'a\nb\nc\n'
pw Panel.qml 'a\nb (mine)\nc\n'; pc "local: one line"
uw Panel.qml 'a\nb (upstream)\nc\n'; up "upstream: one line"
sync_conflict
run resolve-file "$ID" Panel.qml --upstream >/dev/null 2>&1 || fail "resolve-file --upstream failed"
[[ "$(sed -n 2p "$PREPO/Panel.qml")" == "b (upstream)" ]] || fail "resolve-file did not take the upstream side"
[[ -z "$(mctx)" ]] || fail "resolve-file left the file unmerged"
run resolve "$ID" >/dev/null 2>&1 || fail "resolve after resolve-file failed"
[[ -d "$PREPO/.git/rebase-merge" ]] && fail "the rebase is still paused after taking the upstream side"
grep -q "b (upstream)" "$PCLONE/Panel.qml" || fail "the clone does not have the upstream side"
[[ "$(git -C "$PREPO" rev-list --count origin/master..local)" == "0" ]] \
  || fail "a commit that resolves to the upstream side should have been dropped"
git -C "$PREPO" for-each-ref --format='%(refname)' refs/plugpatcher/skipped/ | grep -q . \
  || fail "the dropped empty commit was not kept"
pass "resolving wholly to upstream drops the now-empty commit and keeps it as a ref"

echo "== resolve-hunk --both keeps both versions =="
make_plugin test.both 'a\nb\nc\n'
pw Panel.qml 'a\nmine here\nc\n'; pc "local: one line"
uw Panel.qml 'a\nupstream here\nc\n'; up "upstream: one line"
sync_conflict
run resolve-hunk "$ID" Panel.qml 1 --both >/dev/null 2>&1 || fail "resolve-hunk --both failed"
[[ "$(sed -n 2p "$PREPO/Panel.qml")" == "upstream here" ]] || fail "--both should keep upstream first"
[[ "$(sed -n 3p "$PREPO/Panel.qml")" == "mine here" ]] || fail "--both should keep mine second"
run abort "$ID" >/dev/null 2>&1 || fail "abort after --both failed"
pass "resolve-hunk --both keeps upstream then mine"

echo "== undo: go back to the state before the sync =="
make_plugin test.undo 'a\nb\nc\n'
pw Panel.qml 'a\nb (mine)\nc\n'; pc "local: before the sync"
uw Panel.qml 'a\nb (upstream)\nc\n'; up "upstream: for the undo test"
sync_conflict
[[ "$(conflict_field '.lastBackup // "none"')" != "none" ]] || fail "no pre-sync snapshot was recorded"
run undo "$ID" >/dev/null 2>&1 || fail "undo failed"
[[ -d "$PREPO/.git/rebase-merge" ]] && fail "undo left the rebase paused"
[[ "$(conflict_field '.conflict // "none"')" == "none" ]] || fail "undo did not clear the conflict record"
[[ "$(sed -n 2p "$PREPO/Panel.qml")" == "b (mine)" ]] || fail "undo did not restore the patch content"
[[ "$(git -C "$PREPO" rev-list --count origin/master..local)" == "1" ]] \
  || fail "undo should restore the pre-sync patch commit"
git -C "$PREPO" for-each-ref --format='%(refname)' refs/plugpatcher/undo/ | grep -q . \
  || fail "the state replaced by undo was not kept"
pass "undo restored the pre-sync state and kept the replaced one"

echo "== skip: drop the stuck commit, keep the rest =="
make_plugin test.skip 'l01\nl02\nl03\n'
pw Panel.qml 'l01\nl02 (mine)\nl03\n'; pc "local: first patch commit"
pw Panel.qml 'l01\nl02 (mine)\nl03\nl04 new\n'; pc "local: second patch commit"
uw Panel.qml 'l01\nl02 (upstream)\nl03\n'; up "upstream: clashes with the first commit only"
sync_conflict
stuck="$(cat "$PREPO/.git/rebase-merge/stopped-sha")"
run skip "$ID" >/dev/null 2>&1 || fail "skip failed"
[[ -d "$PREPO/.git/rebase-merge" ]] && fail "skip did not finish the rebase"
git -C "$PREPO" rev-parse --verify --quiet "refs/plugpatcher/skipped/$stuck" >/dev/null \
  || fail "the dropped commit was not kept"
grep -q "l04 new" "$PCLONE/Panel.qml" || fail "skip dropped the wrong commit"
grep -q "l02 (upstream)" "$PCLONE/Panel.qml" || fail "skip did not keep the upstream side"
if grep -q "l02 (mine)" "$PCLONE/Panel.qml"; then fail "skip kept the commit it should have dropped"; fi
[[ "$(conflict_field '.conflict // "none"')" == "none" ]] || fail "skip did not clear the conflict record"
pass "skip dropped the stuck commit, kept the rest, and kept the dropped one as a ref"

echo "== modify/delete: keep the file, then accept the deletion =="
make_plugin test.delmod 'a\nb\nc\n'
pw Panel.qml 'a\nb (mine)\nc\n'; pc "local: modify the file"
git -C "$SEED" rm -q Panel.qml; up "upstream: delete the file"
sync_conflict
json="$(run conflicts "$ID" --json)"
[[ "$(jq -r '.files | length' <<<"$json")" == "1" ]] || fail "the deleted file should be reported"
[[ "$(jq -r '.files[0].hunks | length' <<<"$json")" == "0" ]] || fail "a delete conflict has no text regions"
grep -q "no text conflict" <<<"$(run conflicts "$ID")" || fail "the report should point at the no-text case"
run resolve-file "$ID" Panel.qml --mine >/dev/null 2>&1 || fail "resolve-file --mine should keep the file"
[[ -f "$PREPO/Panel.qml" ]] || fail "the file should have been kept"
grep -qx 'b (mine)' "$PREPO/Panel.qml" || fail "the kept file should hold the patch content"
[[ -z "$(mctx)" ]] || fail "the file should be marked resolved"
run abort "$ID" >/dev/null 2>&1 || fail "abort failed"
pass "resolve-file --mine keeps a file that upstream deleted"

# The upstream still deletes it, and the abort restored the patch commit, so the
# same conflict comes straight back.
sync_conflict
run resolve-file "$ID" Panel.qml --upstream >/dev/null 2>&1 || fail "resolve-file --upstream should accept the deletion"
[[ -e "$PREPO/Panel.qml" ]] && fail "accepting the deletion should remove the file"
[[ -z "$(mctx)" ]] || fail "the deletion should be staged as resolved"
run resolve "$ID" >/dev/null 2>&1 || fail "resolve after accepting the deletion failed"
[[ -e "$PCLONE/Panel.qml" ]] && fail "the clone should not carry the deleted file"
pass "resolve-file --upstream accepts a deletion"

echo "== a plugin without a conflict =="
[[ "$(run conflicts "$ID")" == "$ID: no conflict" ]] || fail "expected a clean report"
[[ "$(run conflicts "$ID" --json | jq -r '.files | length')" == "0" ]] || fail "expected no files"
if run resolve-file "$ID" Panel.qml --mine >/dev/null 2>&1; then fail "resolve-file should refuse without a conflict"; fi
if run skip "$ID" >/dev/null 2>&1; then fail "skip should refuse without a conflict"; fi
pass "conflicts reports a clean plugin and the actions refuse"

echo "== pre-sync snapshots are pruned to the five newest =="
make_plugin test.prune 'a\nb\nc\n'
pw Panel.qml 'a\nb (mine)\nc\n'; pc "local: one line"
i=0
while (( i < 7 )); do
  run sync "$ID" >/dev/null 2>&1 || fail "sync $i failed"
  i=$((i + 1))
done
kept="$(git -C "$PREPO" for-each-ref --format='%(refname)' refs/plugpatcher/pre-sync/ | wc -l)"
[[ "$kept" == "5" ]] || fail "expected 5 kept snapshots, found $kept"
[[ "$(conflict_field '.lastBackup')" == "$(git -C "$PREPO" for-each-ref --sort=refname --format='%(refname)' refs/plugpatcher/pre-sync/ | tail -1)" ]] \
  || fail "the recorded snapshot is not the newest one"
run undo "$ID" >/dev/null 2>&1 || fail "undo after pruning failed"
pass "only the five newest snapshots are kept, and undo still works"

echo "== several conflicted plugins at once =="
make_plugin test.multi1 'a\nb\nc\n'
pw Panel.qml 'a\nb (mine)\nc\n'; pc "local: m1"
uw Panel.qml 'a\nb (upstream)\nc\n'; up "upstream: m1"
sync_conflict
make_plugin test.multi2 'a\nb\nc\n'
pw Panel.qml 'a\nb (mine)\nc\n'; pc "local: m2"
uw Panel.qml 'a\nb (upstream)\nc\n'; up "upstream: m2"
sync_conflict

human="$(run conflicts)"
grep -q "test.multi1: 1 conflicted file(s)" <<<"$human" || fail "the first conflicted plugin is missing"
grep -q "test.multi2: 1 conflicted file(s)" <<<"$human" || fail "the second conflicted plugin is missing"
json="$(run conflicts --json)"
[[ "$(jq -r '.plugins | length' <<<"$json")" == "2" ]] || fail "expected exactly two conflicted plugins"
[[ "$(jq -r '[.plugins[].id] | sort | join(",")' <<<"$json")" == "test.multi1,test.multi2" ]] \
  || fail "the json listed the wrong plugins"
[[ "$(jq -r '.plugins[0].files[0].hunks[0].theirs | join(",")' <<<"$json")" == "b (mine)" ]] \
  || fail "the multi-plugin json lost the patch side"
pass "conflicts with no id reports every conflicted plugin"

echo "ALL CONFLICT TESTS PASSED"
