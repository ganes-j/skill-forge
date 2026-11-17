#!/usr/bin/env bash
# Regression smoke for close-refine. Runs the closer against a scratch state dir (--root), so it
# never touches a real ledger.
#
# Usage: bash tests/smoke-close-refine.sh   (needs bash + jq + /usr/bin/python3)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLOSE="$REPO/skills/skill-forge/close-refine"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/skill-forge"
mkdir -p "$ROOT/counts"
TODAY="$(date +%F)"

fail=0
pass() { echo "  PASS: $1"; }
bad()  { echo "  FAIL: $1"; fail=1; }
close() { "$CLOSE" "$@" --root "$ROOT"; }

# Three ledger lines in three styles. Only demo-skill may be rewritten; the other two must
# survive every close byte-for-byte.
seed() {
  cat > "$ROOT/ledger.jsonl" <<'LEDGER'
{"name":"neighbour","kind":"skill","last_refined":"2026-01-01","refine_threshold":3,"status":"active"}
{"name": "demo-skill", "kind": "skill", "last_refined": "2026-01-01", "refine_threshold": 3, "status": "active"}
{"name": "old-skill",   "kind": "tool", "last_refined": "2026-01-01", "status": "retired"}
LEDGER
  : > "$ROOT/usage.jsonl"
  printf 7 > "$ROOT/counts/demo-skill"
}
snapshot() { cat "$ROOT/ledger.jsonl" "$ROOT/usage.jsonl" "$ROOT/counts/demo-skill" | shasum; }

echo "TEST 1: --dry-run writes nothing"
seed; before="$(snapshot)"
out="$(close demo-skill --dry-run 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ "$(snapshot)" = "$before" ]; then pass "state unchanged"; else bad "dry run changed state (rc=$rc)"; fi
if echo "$out" | grep -q "\"name\":\"demo-skill\",\"ts\":\"$TODAY\",\"event\":\"refined\""; then pass "previews the event line"; else bad "no event preview: $out"; fi

echo "TEST 2: a close performs all three writes"
seed
close demo-skill >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ]; then pass "exit 0"; else bad "exit $rc"; fi
if [ "$(cat "$ROOT/counts/demo-skill")" = "0" ]; then pass "counter reset to 0"; else bad "counter == $(cat "$ROOT/counts/demo-skill")"; fi
if [ "$(jq -r 'select(.name=="demo-skill").last_refined' "$ROOT/ledger.jsonl")" = "$TODAY" ]; then pass "last_refined stamped today"; else bad "last_refined not stamped"; fi
# Compact, exact shape: the readers that filter usage.jsonl match on "name":"x" with no space.
if [ "$(cat "$ROOT/usage.jsonl")" = "{\"name\":\"demo-skill\",\"ts\":\"$TODAY\",\"event\":\"refined\"}" ]; then pass "usage line is the exact compact shape"; else bad "usage line: $(cat "$ROOT/usage.jsonl")"; fi

echo "TEST 3: untouched ledger lines stay byte-identical"
if [ "$(sed -n 1p "$ROOT/ledger.jsonl")" = '{"name":"neighbour","kind":"skill","last_refined":"2026-01-01","refine_threshold":3,"status":"active"}' ] \
  && [ "$(sed -n 3p "$ROOT/ledger.jsonl")" = '{"name": "old-skill",   "kind": "tool", "last_refined": "2026-01-01", "status": "retired"}' ] \
  && [ "$(wc -l < "$ROOT/ledger.jsonl" | tr -d ' ')" = "3" ]; then pass "neighbours preserved, 3 lines"; else bad "ledger restyled"; fi

echo "TEST 4: a second close on the same day is refused"
before="$(snapshot)"
close demo-skill >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(snapshot)" = "$before" ]; then pass "refused, state unchanged"; else bad "second close accepted (rc=$rc)"; fi
close demo-skill --force >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && [ "$(wc -l < "$ROOT/usage.jsonl" | tr -d ' ')" = "2" ]; then pass "--force allows it"; else bad "--force did not close (rc=$rc)"; fi

echo "TEST 5: --no-change logs reviewed-no-change"
seed
close demo-skill --no-change >/dev/null 2>&1
if [ "$(cat "$ROOT/usage.jsonl")" = "{\"name\":\"demo-skill\",\"ts\":\"$TODAY\",\"event\":\"reviewed-no-change\"}" ]; then pass "event is reviewed-no-change"; else bad "usage line: $(cat "$ROOT/usage.jsonl")"; fi
if [ "$(cat "$ROOT/counts/demo-skill")" = "0" ]; then pass "counter still reset"; else bad "counter not reset"; fi

echo "TEST 6: bad targets are refused with nothing written"
seed; before="$(snapshot)"
close no-such-skill >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(snapshot)" = "$before" ]; then pass "unregistered name refused"; else bad "unregistered name accepted (rc=$rc)"; fi
close old-skill >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(snapshot)" = "$before" ]; then pass "retired skill refused"; else bad "retired skill accepted (rc=$rc)"; fi
printf '%s\n' '{"name":"demo-skill","status":"active"}' >> "$ROOT/ledger.jsonl"; before="$(snapshot)"
close demo-skill >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ] && [ "$(snapshot)" = "$before" ]; then pass "duplicated name refused"; else bad "duplicated name accepted (rc=$rc)"; fi

echo
if [ "$fail" = 0 ]; then echo "ALL SMOKE TESTS PASSED"; exit 0; else echo "SMOKE TESTS FAILED"; exit 1; fi
