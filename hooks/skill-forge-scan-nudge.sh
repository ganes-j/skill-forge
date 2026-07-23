#!/usr/bin/env bash
# UserPromptSubmit, gated to your session wrap-up command. Nudge to run a skill-forge
# capability-gap scan as part of wrap-up ("what tool/skill would have helped this session?").
# Advisory, never blocks.
#
# WIRING: this fires when the submitted prompt matches WRAP_PATTERN below. The default is
# 'save-session' — change it to whatever your session wrap-up command/ritual is called.
[ -f "$HOME/.claude/.forge-off" ] && exit 0

WRAP_PATTERN='save-session'

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null)"
printf '%s' "$prompt" | grep -qi "$WRAP_PATTERN" || exit 0
msg="SESSION WRAP-UP: also run a skill-forge capability-gap scan — invoke the skill-forge skill (scan mode) and ask what tool, skill, or command would have saved effort this session (repeated manual steps, hand-rolled API calls, an awkward workflow, a missing capability). Filter HARD: most sessions surface zero gaps, which is the correct outcome — do NOT forge a skill just to have run the loop. If a genuine recurring gap survives, propose it as a build candidate for the maintainer to accept; never build without a go-ahead. Distinct from a lessons-capture nudge (that captures a lesson; this builds a reusable capability)."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}'
exit 0
