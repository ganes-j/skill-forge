#!/usr/bin/env bash
# PostToolUse. Two modes, because a skill gets used two different ways:
#
#   (default)      on the `Skill` tool — a forged skill was invoked by name.
#   --detect-bash  on `Bash` — a forged skill whose payload is a script (a probe runner, a
#                  query runner, a verify script) was driven straight from the shell, which
#                  the Skill tool never sees.
#
# The second mode exists because the first, alone, lies. One script-payload skill's counter read
# 3 for a session that drove its script ~30 times and then hand-rolled 21 one-off scripts around
# it — so the skill looked idle at precisely the moment it had the most evidence for a refine.
# Advisory, never blocks.
[ -f "$HOME/.claude/.forge-off" ] && exit 0

FORGE="$HOME/.claude/skill-forge"
LEDGER="$FORGE/ledger.jsonl"
USAGE="$FORGE/usage.jsonl"
[ -s "$LEDGER" ] || exit 0

mode="skill"
if [ "$1" = "--detect-bash" ]; then mode="bash"; shift; fi

input="$(cat)"
event="${1:-PostToolUse}"

# Bump a skill's counter, log the use, and nudge once per session if it crosses its threshold.
# $1 skill, $2 threshold, $3 event label, $4 session id, $5 last_refined (YYYY-MM-DD, may be empty).
bump_and_nudge() {
  local skill="$1" threshold="$2" label="$3" sid="$4" lastref="$5" safe cfile count marker msg since days lr_epoch
  printf '{"name":"%s","ts":"%s","session":"%s","event":"%s"}\n' \
    "$skill" "$(date -u +%FT%TZ)" "$sid" "$label" >> "$USAGE"

  safe="$(printf '%s' "$skill" | tr -c 'A-Za-z0-9-' '_')"
  cfile="$FORGE/counts/$safe"
  count="$(cat "$cfile" 2>/dev/null || echo 0)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  count=$((count + 1))
  mkdir -p "$FORGE/counts"
  printf '%s' "$count" > "$cfile"

  [ "$count" -ge "$threshold" ] || return 0
  marker="${TMPDIR:-/tmp}/claude-forge-${sid}-${safe}.nudged"
  [ -f "$marker" ] && return 0
  touch "$marker"
  # The date is the counter-evidence. A bare count reads as a verdict and gets relayed as one;
  # "3 days ago" next to it does not. Degrade to the bare phrase if the ledger has no date or
  # BSD `date` cannot parse it — a broken clause must never cost the nudge.
  since="since its last refine"
  if [ -n "$lastref" ]; then
    since="$since on $lastref"
    lr_epoch="$(date -j -f '%Y-%m-%d' "$lastref" +%s 2>/dev/null)"
    if [ -n "$lr_epoch" ]; then
      days=$(( ( $(date +%s) - lr_epoch ) / 86400 ))
      [ "$days" -ge 0 ] && since="$since ($days days ago)"
    fi
  fi
  msg="Forged skill '$skill': counter at $count, threshold $threshold, $since. Before you act on this: the count includes shell commands that merely READ the skill's directory, and a burst of runs in one session inflates it fast — so it is a prompt to look, not a finding. Check the refine date above and how the skill actually behaved in recent real use. Do NOT relay this nudge to the maintainer as a verdict without that check. If it needs work, run the skill-forge skill in refine mode. If it is fine as-is, that is a valid and common outcome — close it by appending {\"name\":\"$skill\",\"ts\":\"<date +%F>\",\"event\":\"reviewed-no-change\"} to ~/.claude/skill-forge/usage.jsonl, resetting the counter, and stamping last_refined. Advisory, not a gate."
  jq -cn --arg m "$msg" --arg e "$event" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$m}}'
}

if [ "$mode" = "bash" ]; then
  # Fast bail with no subprocess at all. Virtually every Bash call misses this, and this hook
  # runs on all of them — so the raw JSON is string-tested before jq is ever spawned.
  case "$input" in
    *.claude/skills/*|*.claude/bin/*) ;;
    *) exit 0 ;;
  esac
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
  [ -z "$cmd" ] && exit 0
  sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"

  while IFS=$'\t' read -r name path threshold lastref; do
    [ -z "$name" ] && continue
    case "$threshold" in ''|*[!0-9]*) threshold=3 ;; esac
    # Ledger paths are written `~/.claude/...`; commands arrive as `~/`, `$HOME/` or absolute.
    # Reducing both to a home-relative token matches all three without three patterns.
    tok="${path%/SKILL.md}"
    tok="${tok#\~/}"; tok="${tok#"$HOME"/}"
    [ -z "$tok" ] && continue
    # Deliberately matching the skill's directory rather than a script path: the payload is as
    # often run as `cd <skilldir> && node <script>` as by full path, and requiring the script
    # name missed exactly that form. Reading SKILL.md from the shell therefore counts too —
    # which is fair, since that is what using a skill without the Skill tool looks like.
    if [[ "$cmd" == *"$tok"* ]]; then
      bump_and_nudge "$name" "$threshold" "ran" "$sid" "$lastref"
    fi
  done <<EOF
$(jq -r 'select((.status // "active") == "active") | [.name, .path, (.refine_threshold // 3), (.last_refined // "")] | @tsv' "$LEDGER" 2>/dev/null)
EOF
  exit 0
fi

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // .tool_input.name // ""' 2>/dev/null)"
[ -z "$skill" ] && exit 0

# Fast reject: not a forged name -> nothing to do. Parse each JSONL entry by name (format-tolerant;
# a fixed-string grep breaks on the ledger's pretty-printed `"name": "x"` spacing).
line="$(jq -c --arg n "$skill" 'select(.name == $n)' "$LEDGER" 2>/dev/null | head -1)"
[ -z "$line" ] && exit 0
status="$(printf '%s' "$line" | jq -r '.status // "active"' 2>/dev/null)"
[ "$status" = "active" ] || exit 0
threshold="$(printf '%s' "$line" | jq -r '.refine_threshold // 3' 2>/dev/null)"
case "$threshold" in ''|*[!0-9]*) threshold=3 ;; esac

lastref="$(printf '%s' "$line" | jq -r '.last_refined // ""' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
ts="$(date -u +%FT%TZ)"

# skill-forge's own `scan` mode is driven by the wrap-up nudge, so counting it guarantees a false
# refine-due nudge every few sessions — the loop inflating its own counter. Log it as a distinct
# event (keeps frequency data, invisible to readers filtering on "invoked"), then stop before the
# counter bump. `build` still counts; `refine` resets the counter anyway.
args="$(printf '%s' "$input" | jq -r '.tool_input.args // ""' 2>/dev/null)"
case "$skill:$args" in
  skill-forge:scan*)
    printf '{"name":"%s","ts":"%s","session":"%s","event":"scan"}\n' "$skill" "$ts" "$sid" >> "$USAGE"
    exit 0 ;;
esac

bump_and_nudge "$skill" "$threshold" "invoked" "$sid" "$lastref"
exit 0
