# Prompt — caching, then windows instead of sheets

Paste this into a fresh session. It covers two pieces of work, in order, and the order matters.

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

## What phase 1 must not skip

`docs/handovers/CACHING_HANDOVER.md` has one line that matters more than the rest: **key the cache
by instance URL.** Settings can be pointed at another tenant, and a cache that is not keyed will
serve one tenant's policies while connected to the other — in an app whose next action might be a
bulk delete.

## Why this order

The cache is what the maintainer feels every day: four full estate scans are reachable in one session
and nothing stops a session doing all four with no change between them. The sheet work is a shape
improvement to two screens plus a payoff for the help guide.

They are also different kinds of risk. The cache is a correctness problem — stale data in front of a
destructive action. The sheet work is a behaviour-preservation problem — a layout change that must
not alter a single byte sent to Jamf. Doing them in one sitting means holding both in mind at once,
which is how one of them gets the less careful half of the session.

## What is already done, so nobody redoes it

The help overhaul is finished — four phases, twenty pages, eleven figures built from the app's real
views, a Spotlight-style search panel, and PDF export. `docs/handovers/HELP_OVERHAUL_HANDOVER.md`
has the proven/unproven table. Its four remaining open questions are the maintainer's calls, not
work to pick up.
