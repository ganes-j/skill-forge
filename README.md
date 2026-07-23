# skill-forge

A self-refining loop for building agent skills — and, more importantly, for *not* building them.

Most "make the agent better" advice tells you to add capabilities. skill-forge is built on the
opposite instinct: the failure mode is sprawl, not scarcity. A pile of half-relevant skills makes
every future decision worse, because the agent has to wade through them to find the one that fits.
So skill-forge treats a new skill as a cost to be justified, not a win to be celebrated. Most
sessions should end with **zero** new skills, and that is the loop working correctly.

When a real gap does survive the filter, skill-forge builds one skill, then tracks whether it
actually earns its place — and refines it from real usage instead of guessing.

## The idea in four claims

1. **Capabilities are not lessons.** A lesson is "remember to do X next time" — it belongs in
   whatever notes/lessons doc you already keep. A capability is "I keep doing X by hand and want a
   reusable doer." Only the second is a forge candidate. Conflating them buries real tools under
   reminders.
2. **Propose, then dispose.** The scan *proposes* a gap. A human *disposes* — accepts or rejects the
   build. The loop never force-builds a skill to look productive.
3. **Zero-gap scans are the healthy outcome.** Sprawl is the failure mode. A scan that rejects three
   near-misses and forges nothing did its job.
4. **Track first, trust on evidence.** A new skill isn't assumed good. Every invocation is counted;
   after it's been used a few times, the loop nudges a refinement pass driven by how it was *actually*
   used — not by how you imagined it would be.

## The loop

```
        session wrap-up
              │
              ▼
        ┌──────────┐   gap survives      ┌──────────┐
        │   scan   │───the hard filter──▶│  propose │
        └──────────┘                     └────┬─────┘
              │ zero gaps                      │ human accepts
              ▼                                ▼
        report clean                     ┌──────────┐
        (the common case)               │  build   │──▶ ledger entry
                                         └────┬─────┘
                                              │
                       every Skill invocation │ (usage hook counts it)
                                              ▼
                                        ┌──────────┐  threshold hit
                                        │  track   │──────────────┐
                                        └──────────┘              ▼
                                                            ┌──────────┐
                                              near-zero use │  refine  │
                                              over time  ◀──┤  or      │
                                              → propose      │  retire  │
                                              retire         └──────────┘
```

- **scan** — at wrap-up, look for a genuine recurring capability gap. Filter hard; report clean if none.
- **build** — forge the accepted candidate (using the `writing-skills` discipline), register a ledger line, smoke-test it.
- **track** — a PostToolUse hook counts every invocation of a forged skill and nudges when it's due for refinement.
- **refine** — read the real usage log, make small evidence-driven edits (sharper trigger description, fix a misfiring step), reset the counter.
- **retire** — a skill used near-zero over a long window gets proposed for retirement. Surfaced for sign-off, never silent.

## What's in the box

```
skills/skill-forge/SKILL.md        the skill itself (scan / build / refine / status modes)
hooks/skill-forge-status.sh        SessionStart — surfaces active forged skills; silent when empty
hooks/skill-forge-usage.sh         PostToolUse(Skill) — counts uses, nudges at threshold
hooks/skill-forge-scan-nudge.sh    UserPromptSubmit — nudges a scan at your wrap-up command
skill-forge/                       empty state scaffold (ledger.jsonl, usage.jsonl, counts/)
settings.snippet.json              the three hook wirings to merge into ~/.claude/settings.json
INSTALL.md                         install + the wrap-up wiring note
```

It's stdlib bash + `jq`. No language runtime, no network, no dependencies beyond `jq` and a
Claude Code install.

## Install

See [INSTALL.md](INSTALL.md). Short version: copy `skills/` and `hooks/` into `~/.claude/`, create
the empty `~/.claude/skill-forge/` state dir, and merge `settings.snippet.json` into your
`~/.claude/settings.json`.

## The wrap-up wiring note (read this — it's the one non-obvious part)

The loop only refines skills it can *see being used*, and it only sees usage through Claude Code's
`Skill` tool. The PostToolUse hook fires on the `Skill` tool — so a forged skill has to be invoked
**through the `Skill` tool** (`/skill-name` or the agent calling it), not merely read or run some
other way, or the usage counter never increments and the refine nudge never fires.

This bit us in practice: the scan step was originally wired as loose prose in a wrap-up command
("also do a capability scan"), and the agent would satisfy it by reasoning inline — never actually
invoking the skill, so nothing got counted. The fix was to make the wrap-up step *require* invoking
skill-forge through the `Skill` tool. If you wire the scan into your own session wrap-up ritual,
wire it the same way: "invoke the skill-forge skill (scan mode)", not "think about gaps."

## Maturity

Honest status, because the whole point of this thing is trusting on evidence rather than assertion.

**One full self-improvement cycle proven, as of 2026-07-23.** A forged skill was built, used across
three real sessions, hit its refine threshold, the usage hook nudged, and a refinement pass ran off
the real usage log. That's the complete build → track → nudge → refine arc closed once, on a real
skill, not a fixture.

What that means: the mechanism works end to end. What it doesn't yet mean: long-run evidence that
the *retire* path fires cleanly, or that the hard filter holds up over dozens of sessions without
drifting toward sprawl. Use it, watch your ledger, and if it starts accumulating skills you never
invoke, that's the signal the filter needs tightening — not that you need more skills.

## License

MIT. See [LICENSE](LICENSE).
