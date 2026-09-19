# Prompt — Help overhaul, phase 2

Paste the block below as the **first message** of a fresh session.

Phase 1 (the Markdown help machinery) is written but **uncommitted and unrun**. The first job is to
look at it, not to write more.

---

```
Read docs/prompts/START_HERE.md and follow it, then read CLAUDE.md's safety invariants and
treat them as binding.

Then read docs/handovers/HELP_OVERHAUL_HANDOVER.md. It describes phase 1 of a help overhaul
that is written but never run: the proven/unproven table is the important part.

Before writing anything, do this in order:

1. Open the app and read all eight help pages. Phase 1 has never been rendered. Tell me
   what is wrong with it — layout, spacing, anything that reads badly — and try the search
   box with "403", "unscoped" and "client secret".
2. Only then start phase 2, which the handover sets out: split modules.md into nine
   per-module topics, and write apis.md and whats-coming.md.

Do not start phase 2 until I have seen what you found in step 1.
```

---

## Why the first step is looking, not writing

Phase 1 replaced a 281-line SwiftUI document with a Markdown parser, a renderer and a search index —
around 870 lines — and every one of them is unproven. The build passes and the files reach the
bundle; that is all that is known. A session that starts by writing nine more Markdown pages is
writing content for a renderer nobody has looked at.

The parser has never seen its own content either. Eight files went in without a single one being
rendered, so an escaping slip or a list that does not close will show up on first read.

## What "done" looks like for phase 2

- Nine module topics, each answering what it lists, what you can do to it, and the one thing that
  surprises people. The handover has the candidate list for that last part.
- `apis.md` — the three APIs the app uses and what each is for, written for an administrator deciding
  what to grant.
- `whats-coming.md` — mobile devices, plus what is in `docs/roadmap/`, stated as intentions rather
  than commitments.
- All of it registered in `HelpLibrary.topics` with summaries and keywords.

## What to leave alone

The four open questions in the handover — sheet versus window, figures, deep links, the disclaimer
wording — are the maintainer's calls. Raise them; do not decide them.

## When phase 2 lands

Update `docs/handovers/HELP_OVERHAUL_HANDOVER.md` to say what was actually proven on screen, then
delete this prompt.
