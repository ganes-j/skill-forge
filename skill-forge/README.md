# Skill-Forge state

The flywheel's memory. The `skill-forge` skill reads and writes these; two hooks feed them.

The ledger is the loop's only durable input — treat it the way a task-router treats its
outcome log: no entry, no learning.

## Files

- **`ledger.jsonl`** — one JSON object per forged skill/tool (the registry). Fields:
  - `name` — skill name (matches the invoked `Skill` name, or the tool/command name)
  - `kind` — `skill` | `tool` | `command`
  - `path` — where it lives
  - `gap` — the capability gap it was forged to close (one line)
  - `created` — YYYY-MM-DD
  - `last_refined` — YYYY-MM-DD of the last refine pass
  - `refine_threshold` — uses-since-refine that trigger a refine nudge (default 3 — "a few times")
  - `status` — `active` | `retired`
- **`usage.jsonl`** — append-only audit, one line per invocation: `{"name","ts","session","event"}`. The refine pass reads this to see *how* a skill has actually been used.
- **`counts/<name>`** — plain integer, uses since last refine. The usage hook increments it; a refine pass resets it to `0`.

Ships empty. These files fill in as you forge and use skills — keep them **out of any public
mirror of your setup** (they name your private skills). See the repo `.gitignore`.

## Loop

1. **scan** (wrap-up) → propose capability gaps → the maintainer accepts one → **build** → new `ledger.jsonl` line.
2. Every `Skill` invocation of a forged name → `skill-forge-usage.sh` appends to `usage.jsonl`, bumps `counts/<name>`.
3. `counts/<name>` reaches `refine_threshold` → hook nudges "due for refinement" → **refine** reads `usage.jsonl`, improves the skill, resets the counter, bumps `last_refined`.

## Kill switch

`touch ~/.claude/.forge-off` — hooks exit silently, the skill declines. Remove the file to re-enable.
