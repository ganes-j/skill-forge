#!/usr/bin/env bash
# SessionStart. Surface active forged skills (and any due for refinement) so they stay
# top-of-mind and get invoked when their scenario recurs. Silent when the ledger is empty
# (dormant until the first skill is forged) or the forge is off.
[ -f "$HOME/.claude/.forge-off" ] && exit 0

FORGE="$HOME/.claude/skill-forge"
LEDGER="$FORGE/ledger.jsonl"
[ -s "$LEDGER" ] || exit 0

active="$(jq -r 'select(.status=="active") | .name' "$LEDGER" 2>/dev/null)"
[ -z "$active" ] && exit 0

names=""; n=0; due=""
while IFS= read -r name; do
  [ -z "$name" ] && continue
  n=$((n + 1))
  names="${names:+$names, }$name"
  safe="$(printf '%s' "$name" | tr -c 'A-Za-z0-9-' '_')"
  c="$(cat "$FORGE/counts/$safe" 2>/dev/null || echo 0)"
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  thr="$(jq -c --arg n "$name" 'select(.name == $n)' "$LEDGER" 2>/dev/null | head -1 | jq -r '.refine_threshold // 3' 2>/dev/null)"
  case "$thr" in ''|*[!0-9]*) thr=3 ;; esac
  [ "$c" -ge "$thr" ] && due="${due:+$due, }$name"
done <<EOF
$active
EOF

msg="Skill-Forge: $n active forged skill(s) [$names]. Invoke one when its scenario recurs."
[ -n "$due" ] && msg="$msg Due for refinement: $due — run skill-forge (refine mode)."

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0
