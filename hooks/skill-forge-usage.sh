#!/usr/bin/env bash
# PostToolUse on the `Skill` tool. When a *forged* skill (one listed in the skill-forge
# ledger) is invoked, log the use and bump its uses-since-refine counter. When that counter
# reaches the skill's refine_threshold ("a few times"), nudge to run skill-forge refine mode.
# Advisory, never blocks. Non-forged skills (the common case) exit immediately and cheaply.
[ -f "$HOME/.claude/.forge-off" ] && exit 0

FORGE="$HOME/.claude/skill-forge"
LEDGER="$FORGE/ledger.jsonl"
USAGE="$FORGE/usage.jsonl"
[ -s "$LEDGER" ] || exit 0

input="$(cat)"
event="${1:-PostToolUse}"
skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // .tool_input.name // ""' 2>/dev/null)"
[ -z "$skill" ] && exit 0

# Fast reject: not a forged name -> nothing to do. Exact field match (fixed string).
line="$(grep -F "\"name\":\"$skill\"" "$LEDGER" 2>/dev/null | head -1)"
[ -z "$line" ] && exit 0
status="$(printf '%s' "$line" | jq -r '.status // "active"' 2>/dev/null)"
[ "$status" = "active" ] || exit 0
threshold="$(printf '%s' "$line" | jq -r '.refine_threshold // 3' 2>/dev/null)"
case "$threshold" in ''|*[!0-9]*) threshold=3 ;; esac

sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
ts="$(date -u +%FT%TZ)"
printf '{"name":"%s","ts":"%s","session":"%s","event":"invoked"}\n' "$skill" "$ts" "$sid" >> "$USAGE"

safe="$(printf '%s' "$skill" | tr -c 'A-Za-z0-9-' '_')"
cfile="$FORGE/counts/$safe"
count="$(cat "$cfile" 2>/dev/null || echo 0)"
case "$count" in ''|*[!0-9]*) count=0 ;; esac
count=$((count + 1))
mkdir -p "$FORGE/counts"
printf '%s' "$count" > "$cfile"

if [ "$count" -ge "$threshold" ]; then
  marker="${TMPDIR:-/tmp}/claude-forge-${sid}-${safe}.nudged"
  if [ ! -f "$marker" ]; then
    touch "$marker"
    msg="Forged skill '$skill' has been used $count times since its last refine (threshold $threshold) — it's due for a refinement pass. Run the skill-forge skill in refine mode: read ~/.claude/skill-forge/usage.jsonl for '$skill', make small evidence-driven improvements, then reset its counter and stamp last_refined. Advisory, not a gate."
    jq -cn --arg m "$msg" --arg e "$event" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$m}}'
  fi
fi
exit 0
