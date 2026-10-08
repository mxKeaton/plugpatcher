#!/usr/bin/env bash
# Isolated smoke test for the plugpatcher CLI git logic.
# Uses a throwaway HOME and stub `omarchy*` commands. Touches nothing real.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export PATH="$T/stubs:$PATH"
mkdir -p "$HOME/.config/omarchy/plugins" "$T/stubs" "$T/upstream.git"

pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

# ---- upstream bare repo + seed ----
git init -q --bare "$T/upstream.git"
git init -q "$T/seed"
git -C "$T/seed" config user.email t@t
git -C "$T/seed" config user.name t
cat > "$T/seed/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"test.plugin","name":"Test","version":"1.0.0","kinds":["panel"],"entryPoints":{"panel":"Panel.qml"}}
JSON
printf 'line one\n' > "$T/seed/Panel.qml"
git -C "$T/seed" add -A && git -C "$T/seed" commit -qm init
git -C "$T/seed" branch -M master
git -C "$T/seed" remote add origin "$T/upstream.git"
git -C "$T/seed" push -q origin master

# ---- "installed" plugin (a clone of upstream) ----
git clone -q "$T/upstream.git" "$HOME/.config/omarchy/plugins/test.plugin"

# ---- stubs ----
mkstub() { cat > "$T/stubs/$1"; chmod +x "$T/stubs/$1"; }
mkstub omarchy <<'EOF'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >> "$HOME/.omarchy-calls"
exit 0
EOF
mkstub omarchy-shell <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
mkstub omarchy-notification-send <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
mkstub omarchy-default-agent <<'EOF'
#!/usr/bin/env bash
echo pi
EOF
mkstub omarchy-plugin-list <<'EOF'
#!/usr/bin/env bash
# emits an array of {"id": ...} from installed manifests
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
mkstub plugpatcher-unused <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

CLI="$REPO/bin/plugpatcher"
run() { "$CLI" "$@"; }

echo "== setup =="
run setup test.plugin >/dev/null 2>&1 || fail "setup exited non-zero"
[[ -f "$HOME/.local/share/plugpatcher/test.plugin.json" ]] || fail "metadata missing"
CLONE="$HOME/.config/omarchy/plugins/local.plugin"
[[ -f "$CLONE/manifest.json" ]] || fail "clone not generated"
[[ "$(jq -r .id "$CLONE/manifest.json")" == "local.plugin" ]] || fail "clone id not rewritten"
[[ "$(jq -r .omarchy.clonedFrom "$CLONE/manifest.json")" == "test.plugin" ]] || fail "clonedFrom not set"
grep -q "plugin enable local.plugin" "$HOME/.omarchy-calls" || fail "clone not enabled"
pass "setup generated local.plugin and enabled it"

echo "== edit + sync (clean upstream advance) =="
printf 'line one\nline two (edited)\n' > "$HOME/.local/share/plugpatcher/test.plugin/Panel.qml"
git -C "$HOME/.local/share/plugpatcher/test.plugin" add -A
git -C "$HOME/.local/share/plugpatcher/test.plugin" -c user.email=t@t -c user.name=t commit -qm "local edit"
# advance upstream
printf 'upstream addition\n' > "$T/seed/Other.qml"
git -C "$T/seed" add -A && git -C "$T/seed" commit -qm "upstream change"
git -C "$T/seed" push -q origin master
run sync test.plugin >/dev/null 2>&1 || fail "sync exited non-zero"
grep -q "line two (edited)" "$CLONE/Panel.qml" || fail "local edit lost after sync"
[[ -f "$CLONE/Other.qml" ]] || fail "upstream change not merged into clone"
pass "sync rebased local edit on top of upstream and regenerated clone"

echo "== sync conflict aborts cleanly =="
printf 'conflicting upstream\n' > "$T/seed/Panel.qml"
git -C "$T/seed" add -A && git -C "$T/seed" commit -qm "conflicting upstream change"
git -C "$T/seed" push -q origin master
printf 'conflicting local\n' > "$HOME/.local/share/plugpatcher/test.plugin/Panel.qml"
git -C "$HOME/.local/share/plugpatcher/test.plugin" add -A
git -C "$HOME/.local/share/plugpatcher/test.plugin" -c user.email=t@t -c user.name=t commit -qm "conflicting local"
if run sync test.plugin >/dev/null 2>&1; then fail "sync should have reported a conflict"; fi
[[ "$(git -C "$HOME/.local/share/plugpatcher/test.plugin" status --porcelain | wc -l)" -eq 0 ]] || fail "repo left dirty after aborted sync"
pass "sync aborted on conflict and left the repo clean"

echo "== remove =="
run remove test.plugin >/dev/null 2>&1 || fail "remove exited non-zero"
[[ ! -e "$CLONE" ]] || fail "clone not removed"
[[ ! -e "$HOME/.local/share/plugpatcher/test.plugin.json" ]] || fail "metadata not removed"
grep -q "plugin enable test.plugin" "$HOME/.omarchy-calls" || fail "original not restored"
pass "remove restored the original and deleted the clone"

echo "ALL SMOKE TESTS PASSED"
