# Session prompt — help as a PDF

Hand the block below to a fresh session.

---

```
Read docs/prompts/START_HERE.md and follow it, then read CLAUDE.md's safety invariants and
treat them as binding. This app writes to a live production Jamf instance.

Then read these two, in this order, and treat them as the specification:
  docs/roadmap/HELP_PDF_EXPORT.md       — the intent, and the three ways this already failed
  docs/handovers/HELP_PDF_EXPORT_HANDOVER.md — the state of the code today, and the traps

The guide needs to export a page, or the whole thing, as a PDF — for handing the Privileges
page to a security team without them needing the app.

Do NOT use NSPrintOperation. It was tried on 19 September 2026 and removed: it printed white
text on a white page, then printed nothing at all, then paginated forty pages for twenty
topics. The roadmap entry has all three and why.

Prove the body text is black before building anything on top of it. One page, one paragraph,
opened in Preview. That is the trap that cost the first attempt twice — the app forces
.preferredColorScheme(.dark), and an NSHostingView inherits the dark *appearance*, which
.environment(\.colorScheme, .light) does not touch.

Build the PDF as Data and write it the way the CSV exports already do — compose in memory,
then one NSSavePanel that asks where to save, writes, and reports.
ExportService.saveCSVToFile(content:defaultName:) is the door to copy.

Try ImageRenderer: its render { size, context in … } gives a CGContext, so a CGPDFContext can
be driven a page at a time, and the figures survive because they are still views. This is a
recommendation, not a finding — nobody has rendered a page of this guide. Treat the first
spike as finding out whether it works at all.

Pagination is the real work: measure each HelpBlock and start a new page rather than letting
a callout or a numbered list be cut in half. HelpMarkdown.parse gives you typed blocks, which
is what makes this tractable — walk those rather than re-deriving the structure.

Do not re-draw a figure by hand. HelpFigures instantiates the real views; that is the whole
lesson of HELP_OVERHAUL_HANDOVER.md phase D.

Stamp every export with the app version and the date. The guide's claim is that it matches
the build; a PDF is a copy that stops being true the moment either moves.

Build after every phase. There is no test target — do not claim tests ran. I run the app
myself, so do not launch it; tell me what to look at and I will tell you what I see. I will
also want to see the PDF, so hand me the file.
```

---

## If he would rather do something else

The PDF is the last phase of the original three-phase plan, but it is not the only thing open. In
rough order of how ready each is:

- **Two more sheets to convert** — `BlueprintEditorSheet` and `PackageUploadPage`, the remaining
  candidates in `docs/roadmap/SHEET_NAVIGATION.md`. Its handover now records every trap the first
  two conversions hit, so a third should be markedly cheaper. **This is the most shovel-ready.**
- **`docs/roadmap/POLICY_NAME_SUGGESTIONS.md`** — the multi-label case, where one template has to
  serve every policy in a run and there is no way to correct one of them. Narrower than it looks;
  the single-label case is already solved by the template field.
- **`docs/roadmap/CACHING.md`** — what is left of it: Blueprints, a maximum age, per-domain
  invalidation. All deliberately deferred, none urgent.
- **The four deleted help figures.** Still cannot come back: `DeploymentConfigSheet`'s steps read
  `@State` directly rather than taking values, so a figure has nothing to instantiate. Making them
  value-taking is the same work `SHEET_NAVIGATION.md` describes and would pay for itself twice.

## What this session did, so nobody redoes it

20 September 2026, all confirmed on screen by the maintainer:

- **The session cache** — every Jamf Pro read, keyed by instance URL, cleared by Refresh and by any
  write, with a Live/Cached switch in Settings. The Installomator module's duplicate estate scan was
  deleted (109 lines) and derived from `scanPolicyEstate` instead, and the scan now survives being
  navigated away from.
- **Settings is a window** with a four-page rail and setup steps that deep-link into the guide.
- **The Installomator deployment is a stepped window** — seven steps ending in Review & Deploy,
  rebuilt per deployment, with a shared `confirmWindowClose` guard. **Its requests are unchanged:**
  every XML builder, validation path and throttle was verified untouched by diff.
- **Reset Window Size** (⌃⌘0), a **Refresh button on the Dashboard**, and the Installomator header
  no longer collapses when narrowed.
- The app menu reads **Jamf Commander** rather than JamfCommander.

### The Unused audit was giving a different answer every time — fixed, and worth reading

It reported 120, 122, 124, 125, 126, 127, 128, 130 for the same estate within minutes. It now
reports 133 consistently, and **133 was always the truth** — every lower number was a lost profile.

Three faults, found by elimination from the maintainer's own screenshots (only the *Not scoped*
figure moved; policies and packages were constant, which put it entirely in profiles):

1. **`fetchProfiles` fanned out over every profile at once** — `group.addTask` per profile, 152
   simultaneous requests, no batching, no delay, no retry, under a comment claiming it limited
   concurrency. Jamf throttled it and a varying number failed. **This was the cause.** It is now
   batches of 10 with 0.5s gaps and three attempts, as `services-and-networking.md` requires of
   every bulk read. *If another count ever wanders, look for this shape first.*
2. **A failed hydration was indistinguishable from an answer.** `ConfigProfile.isActive` defaults to
   `true`, so an unread profile was silently counted as scoped. `ConfigProfile.scopeIsKnown` now
   records whether the scope was ever read, `RedundantAudit` refuses to judge a profile without it,
   and `fetchProfiles` will not cache a list with holes in it.
3. **The Dashboard tile's progressive count kept counting after the total was final.** Its bumps are
   fire-and-forget tasks and the late ones landed on the finished figure. A run token discards them.

**The lesson for anything similar:** an audit that decides what nothing uses must distinguish
*unknown* from *unused*, and must not depend on how many requests happened to survive.

**Still unproven against the tenant: no policy has actually been created through the new deployment
window.** The diff shows the writes are untouched, which is not the same as having watched one land.

**A layout-recursion warning was found and fixed** — the converted category step had a `List`
inside a `ScrollView`. `SHEET_NAVIGATION_HANDOVER.md` records it as the thing to watch for in the
remaining two conversions, along with the reason it is easily mistaken for fixed (AppKit logs it
once per process, so only a fresh launch tests it).
