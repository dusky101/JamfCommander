# New session prompt

Open a Claude Code session in the JamfCommander repository and paste the block below as the **first
message**. Nothing else needs saying until it answers.

`CLAUDE.md` already tells a new session to orient itself, so this is belt and braces — but it is the
version that *proves* the reading happened rather than assuming it.

---

```
Before doing anything, read docs/prompts/START_HERE.md and follow it: the reading order,
what each module does, and the things that will catch you out. Then read CLAUDE.md's safety
invariants and treat them as binding — this app writes to a live production Jamf instance.

Confirm you have read both by telling me, in one line each: which two sidebar labels do not
match their folder names, and why a cancelled request must not be retried.

Then wait. I will tell you what we are working on.
```

---

## Checking the answer

The two questions cannot be answered quickly from the code — they live only in the documents. A wrong
or woolly answer means the reading did not happen, and you have found that out before anything was
written rather than after it deleted something.

**Expected answers:**

1. **The label/folder mismatches.** `Modules/Packages/` is the module labelled **Installomator**, and
   `Modules/Redundant/` is the one labelled **Unused**. Both are deliberate and documented in the
   code; the second was renamed because "redundant" reads as *duplicated for resilience* to an
   infrastructure audience.
2. **Cancelled requests.** Leaving a module tears down its task, so every request it had in flight is
   cancelled. Those can never succeed on a retry, so retrying them three times with backoff — which
   this app used to do — burns work and floods the console with one failure per policy.

If either answer is wrong, say so and have it read the files properly before going further. Do not let
it start on code it has not oriented itself for.

## Starting on something specific

Once it has answered, say what the work is. If it is a roadmap item, name the file:

- `docs/roadmap/CACHING.md` — per-domain caching
- `docs/roadmap/SCRIPT_USAGE.md` — which policies run a script

If it is one of the two existing handovers — the sidebar restructure or the Help overhaul, both in
`docs/handovers/` — tell it to **re-verify the code facts first**. Both were written before their work
began, which is what `.claude/rules/docs-workflow.md` now forbids, and the sidebar in particular moved
twice after its handover was written.

## What is not proven

Worth saying out loud at the start of a session, because a handover can imply more confidence than the
code has earned. As of 19 September 2026:

- **Script category moves have never run.** `moveScript` is read-modify-write against
  `PUT api/v1/scripts/{id}`. Test it on one disposable script and confirm the script's *contents*
  survive, not just its category.
- **Script delete has never run** either, though `deleteScript` predates this work.
- **Several Blueprints writes have never run** — see `docs/handovers/BLUEPRINTS_HANDOVER.md`, which
  has the full proven/unproven table.
