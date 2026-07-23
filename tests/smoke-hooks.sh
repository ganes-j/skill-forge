#!/usr/bin/env bash
# Regression smoke for the skill-forge hooks. Runs each hook in an isolated scratch HOME
# against a PRETTY-PRINTED ledger — the exact format the writer emits and the format that a
# fixed-string grep silently fails to match. If the hooks ever regress to grep-ing JSON,
# TEST 2 (usage counter) and the threshold detection in TEST 3 go dead and this fails.
#
# Usage: bash tests/smoke-hooks.sh   (needs bash + jq)
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/home/.claude"
mkdir -p "$FAKE/hooks" "$FAKE/skill-forge/counts"
cp "$REPO"/hooks/skill-forge-*.sh "$FAKE/hooks/"
chmod +x "$FAKE/hooks/"*.sh
: > "$FAKE/skill-forge/ledger.jsonl"
: > "$FAKE/skill-forge/usage.jsonl"

fail=0
pass() { echo "  PASS: $1"; }
bad()  { echo "  FAIL: $1"; fail=1; }

# Sandbox TMPDIR too: the usage hook dedups its nudge with a marker in $TMPDIR, so a run must
# not inherit a marker left by an earlier run (fixed session ids would otherwise collide).
run() { HOME="$TMP/home" TMPDIR="$TMP" bash "$FAKE/hooks/$1" "${2:-}"; }

echo "TEST 1: status hook is silent on an empty ledger"
out="$(run skill-forge-status.sh </dev/null)"
if [ -z "$out" ]; then pass "silent when nothing is forged"; else bad "produced output: $out"; fi

# Pretty-printed ledger entry (space after every colon) — the regression case.
cat > "$FAKE/skill-forge/ledger.jsonl" <<'EOF'
{
  "name": "demo-skill",
  "kind": "skill",
  "path": "x",
  "gap": "g",
  "created": "2026-01-01",
  "last_refined": "2026-01-01",
  "refine_threshold": 3,
  "status": "active"
}
EOF
PAYLOAD='{"tool_input":{"skill":"demo-skill"},"session_id":"verify"}'

echo "TEST 2: usage hook logs + increments against a pretty-printed ledger"
echo "$PAYLOAD" | run skill-forge-usage.sh PostToolUse >/dev/null
cnt="$(cat "$FAKE/skill-forge/counts/demo-skill" 2>/dev/null || echo MISSING)"
if [ "$cnt" = "1" ]; then pass "counts/demo-skill == 1"; else bad "counts/demo-skill == $cnt (grep-JSON regression?)"; fi
if grep -q '"name":"demo-skill"' "$FAKE/skill-forge/usage.jsonl"; then pass "usage.jsonl logged the invocation"; else bad "usage.jsonl not written"; fi

echo "TEST 3: status hook surfaces the active skill + honors its threshold"
out3="$(run skill-forge-status.sh </dev/null)"
if echo "$out3" | grep -q 'demo-skill'; then pass "surfaces active forged skill"; else bad "did not surface skill"; fi

echo "TEST 4: refine nudge fires once the threshold is reached"
echo "$PAYLOAD" | run skill-forge-usage.sh PostToolUse >/dev/null   # count -> 2
echo "$PAYLOAD" | run skill-forge-usage.sh PostToolUse >/dev/null   # count -> 3
nudge="$(echo '{"tool_input":{"skill":"demo-skill"},"session_id":"fresh"}' | run skill-forge-usage.sh PostToolUse)"
if echo "$nudge" | grep -q 'due for a refinement'; then pass "nudge fired at threshold"; else bad "no nudge at threshold"; fi

echo "TEST 5: kill switch silences every hook"
touch "$TMP/home/.claude/.forge-off"
ks="$(echo "$PAYLOAD" | run skill-forge-usage.sh PostToolUse; run skill-forge-status.sh </dev/null)"
if [ -z "$ks" ]; then pass "silent when .forge-off exists"; else bad "not silenced"; fi

echo
if [ "$fail" = 0 ]; then echo "ALL SMOKE TESTS PASSED"; exit 0; else echo "SMOKE TESTS FAILED"; exit 1; fi
