# Prompt — caching, then windows instead of sheets, then the PDF

Paste this into a fresh session. It covers three pieces of work, in order, and the order matters.

---

```
Read docs/prompts/START_HERE.md and follow it, then read CLAUDE.md's safety invariants and
treat them as binding. This app writes to a live production Jamf instance.

Then read these two, in this order, and treat them as the specification:
  docs/roadmap/CACHING.md              — the intent, and my own words about what I want
  docs/handovers/CACHING_HANDOVER.md   — the state of the code today, and the traps

Phase 1 is the cache, and it is the whole of what I want first. Do not start the sheet work.

Build a per-domain, in-memory session cache for JamfAPIService:
  - Keyed by instance URL. This is not optional — I have Production and Sandbox, and a cache
    that serves one tenant's policies while connected to the other is a bulk delete against
    the wrong estate.
  - Invalidated by the Refresh button and by any write this app makes.
  - Visible: the app must say on screen when the data it is showing was read.
  - Refresh always bypasses it.

Start with policies, end to end, and show me that one domain working before widening it.
Policies are the expensive one and they are what four different screens re-read today.

Do not touch the throttling. Batches of 10 with 0.5s gaps exist so a large run does not trip
Jamf's rate limiting; doing the work four times is the problem, not the pace of it.

Build after every phase. There is no test target — do not claim tests ran. I run the app
myself, so do not launch it; tell me what to look at and I will tell you what I see.
```

---

## When phase 1 lands

Update `docs/handovers/CACHING_HANDOVER.md` with what was actually proven against the tenant, trim
`docs/roadmap/CACHING.md` to whatever remains, and only then move to phase 2 below.

---

```
Phase 2. Read:
  docs/roadmap/SHEET_NAVIGATION.md
  docs/handovers/SHEET_NAVIGATION_HANDOVER.md

I want windows, not sheets — the help guide was converted on 19 September 2026 and it is the
worked example. Copy that pattern. The handover names the four files it touched.

Do ConfigurationView first, not the deployment sheet. It is the rehearsal, and it is the only
candidate where a mistake cannot reach a Mac. Show me that before going near Installomator.

Then DeploymentConfigSheet, with one rule: the requests it produces must be byte-identical
before and after. Move the section views; do not touch the state they read, the XML they
build, or the throttling.

Make the sections take values and callbacks rather than bindings. That is the decision that
also lets the help guide illustrate them — four figures were deleted because it could not.
See HELP_OVERHAUL_HANDOVER.md, phase D, and do not re-draw a figure by hand.
```

---

```
Phase 3. Read:
  docs/roadmap/HELP_PDF_EXPORT.md

The guide needs to export a page, or the whole thing, as a PDF — for handing the Privileges
page to a security team without them needing the app.

Do NOT use NSPrintOperation. That was tried on 19 September 2026 and removed: it printed
white text on a white page, then printed nothing at all, then paginated forty pages for
twenty topics. The roadmap entry has the three failures and why.

Build the PDF as Data and write it the way the CSV exports already do — compose in memory,
then one NSSavePanel that asks where to save, writes, and reports. ExportService
.saveCSVToFile(content:defaultName:) is the door to copy, and exportAllDataToZip does the
same for a ZIP.

Try ImageRenderer: its render { size, context in … } gives a CGContext, so a CGPDFContext can
be driven a page at a time, and the figures survive because they are still views.

Prove the body text is black before building anything on top of it. That is the trap that
cost the first attempt, and it cost it twice.

Pagination is the real work: measure each HelpBlock and start a new page rather than letting
a callout or a numbered list be cut in half.

Stamp every export with the app version and the date. The guide's claim is that it matches
the build; a PDF is a copy that stops being true the moment either moves.
```

---

## What phase 1 must not skip

`docs/handovers/CACHING_HANDOVER.md` has one line that matters more than the rest: **key the cache
by instance URL.** Settings can be pointed at another tenant, and a cache that is not keyed will
serve one tenant's policies while connected to the other — in an app whose next action might be a
bulk delete.

## Why this order

The PDF is last because it is the least urgent and the only one with no working starting point —
the first attempt was removed, so phase 3 begins from an empty file and a list of what not to do.

The cache is what the maintainer feels every day: four full estate scans are reachable in one session
and nothing stops a session doing all four with no change between them. The sheet work is a shape
improvement to two screens plus a payoff for the help guide.

They are also different kinds of risk. The cache is a correctness problem — stale data in front of a
destructive action. The sheet work is a behaviour-preservation problem — a layout change that must
not alter a single byte sent to Jamf. Doing them in one sitting means holding both in mind at once,
which is how one of them gets the less careful half of the session.

## What is already done, so nobody redoes it

The help overhaul is finished: **20 topics**, **14 figures** — each one instantiating the view its
module actually uses, never a drawing of it — a search panel that opens over the page and closes
when you click away, and the guide living in **its own window** rather than a sheet.
`docs/handovers/HELP_OVERHAUL_HANDOVER.md` has the proven/unproven table, and the right-hand column
is long: almost none of it has been read on screen by the sessions that wrote it.

**There is no PDF export.** It was attempted on 19 September 2026 and removed — see phase 3 above,
and `docs/roadmap/HELP_PDF_EXPORT.md` for the three ways it failed.

Two open questions remain and both are the maintainer's calls, not work to pick up: **deep links
from module headers into the guide** (`HelpPresenter.request(_:)` exists and nothing calls it), and
**whether the unofficial/disclaimer wording on `welcome.md` is what he wants**.
