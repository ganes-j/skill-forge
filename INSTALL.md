# Installing skill-forge

Requirements: [Claude Code](https://claude.com/claude-code), `jq`, and a POSIX shell. No language
runtime or network access.

## 1. Copy the skill and hooks into `~/.claude/`

From a clone of this repo:

```bash
cp -R skills/skill-forge   ~/.claude/skills/
cp    hooks/skill-forge-*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/skill-forge-*.sh
```

## 2. Create the empty state dir

```bash
mkdir -p ~/.claude/skill-forge/counts
: > ~/.claude/skill-forge/ledger.jsonl
: > ~/.claude/skill-forge/usage.jsonl
```

Copy `skill-forge/README.md` from this repo into `~/.claude/skill-forge/` too if you want the
state-format reference on hand. The state files stay empty until you forge your first skill — every
hook is dormant on an empty ledger, so nothing fires until there's something to track.

## 3. Merge the hook wiring into `~/.claude/settings.json`

`settings.snippet.json` is a **fragment**, not a drop-in file. Merge its four entries into the
matching arrays of your existing `~/.claude/settings.json`:

- `SessionStart` → `skill-forge-status.sh` (surfaces your active forged skills each session)
- `PostToolUse` matcher `"Skill"` → `skill-forge-usage.sh PostToolUse` (counts usage, nudges refine)
- `UserPromptSubmit` → `skill-forge-scan-nudge.sh` (nudges a scan at your wrap-up command)

If you already have blocks for these events, add the skill-forge command to the existing block's
`hooks` array rather than creating a duplicate event block. Claude Code runs each command through a
shell, so `$HOME` expands; absolute paths work too.

## 4. Wire the scan into your wrap-up ritual

Two parts, and the second is the one people miss:

**a. Point the nudge hook at your wrap-up command.** `skill-forge-scan-nudge.sh` fires when a
submitted prompt matches `WRAP_PATTERN` (default `save-session`). Edit that variable near the top of
the hook to match whatever your session-wrap-up command or phrase is.

**b. Make the scan step invoke the skill through the `Skill` tool.** The usage counter only
increments when a forged skill is called via Claude Code's `Skill` tool. If your wrap-up step is
loose prose ("also think about what would've helped"), the agent will satisfy it by reasoning inline
and nothing gets counted. Write the step as an explicit instruction to *invoke the skill-forge skill
in scan mode*. This is the single most common wiring mistake — see the README's wrap-up note.

## 5. Verify

Start a fresh Claude Code session. With an empty ledger, skill-forge is silent — that's correct.

- **Status hook is silent on empty state:** `bash ~/.claude/hooks/skill-forge-status.sh </dev/null; echo "exit=$?"` → no output, `exit=0`.
- **Usage hook increments a count:** invoke a skill named in your ledger through the `Skill` tool and check `cat ~/.claude/skill-forge/counts/<name>`.

Then run your wrap-up command and confirm the scan nudge appears.

## Kill switch

`touch ~/.claude/.forge-off` disables everything — hooks exit silently and the skill declines. Remove
the file to re-enable.

## Uninstall

```bash
rm -rf ~/.claude/skills/skill-forge ~/.claude/hooks/skill-forge-*.sh ~/.claude/skill-forge
```

Then remove the four hook entries from `~/.claude/settings.json`.
