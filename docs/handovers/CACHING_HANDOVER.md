# Handover — per-domain caching

**State at handover:** 19 September 2026, app version 9.0. **Nothing is built.** This is the state of
the code the work starts from, and the decisions that are already settled.

Read `docs/roadmap/CACHING.md` first — it holds the intent and the maintainer's own words. This file
holds what is true about the code today.

---

## Proven — and what is NOT

| Established | Not established |
| --- | --- |
| The cost is real and measured: see the four scan sites below | No cache of any kind exists |
| The maintainer has settled **in memory**, and **Refresh or any write** invalidates | Whether a write dirties everything or only its own domains |
| Every Classic write already funnels through one place | Whether the Pro API writes do |
| The Dashboard and the Unused module run the same scan seconds apart | What the second overlay says, or whether it blocks |

## Why now

The Dashboard grew an Unused tile on 19 September 2026, and the maintainer immediately watched the
consequence: *"it takes ages to load the dashboard but then if i click on unused it then reloads the
data"*. Both run `scanPolicyEstate`, which reads **every policy in the tenant**, against data that
cannot have changed in between.

**There are now four full estate scans reachable in one session**, and nothing stops a session doing
all four with no change between them:

1. `DashboardView.loadUnusedTile` — for the Unused tile.
2. `RedundantDashboardView.load` — the Unused module.
3. `AddPackageView` — the Packages **Deployed** tab.
4. `ExportService` — Export All.

On a tenant of ~250 policies each is 250 hydration calls, deliberately throttled in batches of 10
with 0.5s gaps. The throttling is not the problem and must not be touched; doing the work four times
is.

## What the code looks like today

- **Reads** — roughly ten fetch methods across `JamfAPIService` and its extensions. None consults
  anything before going to Jamf.
- **Writes** — every **Classic** write funnels through `JamfAPIService.genericRequest`, which already
  calls `RefreshCoordinator.shared.requestRefresh()`. That is the hook, and it is already there.
  **Check whether the Pro API writes go through an equivalent** — `moveScript`, the package upload,
  the Blueprints writes — because a write that does not signal is a cache that goes stale silently,
  which is the failure mode that matters.
- **Module lifetime** — `ContentView` puts `.id(selection.module)` on the module pane, so switching
  module destroys the view and its `@State`. That is *why* everything refetches, and it is also why a
  cache has to live in the service or beside it, not in a view.

## Decisions already made

From the maintainer, 19 September 2026: *"caching the data once loaded in memory and only updating it
if the refresh button is pressed on window or something is added deleted updated moved. so any update
to jamf from the app makes the data refresh."*

- **In memory**, for the session. Not on disk. This removes the whole privacy question in
  `CACHING.md` trap 2 — no tenant data is written anywhere — and it removes the encryption decision.
- **Two things invalidate:** the Refresh button, and any write this app makes.
- **It does not survive relaunch**, as a consequence.

## The one thing still to decide, and it is most of the work

His two descriptions differ, and the difference is the size of the job:

- The original sketch was **per domain**: *"if a pkg is added then the policies and pkg cache needs
  refreshing … but the profiles and the computers and blueprints and scripts wouldn't need to be
  refreshed"*.
- The newer one is **blunt**: *"any update to jamf from the app makes the data refresh"*.

Blunt is a fraction of the effort and can never serve something stale. Per-domain is faster and needs
a correct mapping written down per write method — and getting that mapping wrong shows stale data
immediately before a destructive action, which is a correctness bug, not a performance one.

**Recommendation: build blunt first.** Measure whether a full invalidation after a write is actually
slow enough in practice to justify the mapping. It probably is not: writes are rare compared with
module switches, and module switches are what hurts today.

## Traps

- **Key the cache by instance URL.** Settings can be pointed at another tenant, and the maintainer
  has Production and Sandbox. A cache that is not keyed will serve one tenant's policies while
  connected to the other. In an app whose next action might be a bulk delete, that is not a display
  bug. This is the single most important line in this file.
- **Staleness has to be visible.** A cached view identical to a fresh one is how somebody deletes a
  policy that was already deleted. Whatever is built must say, on screen, when the data was read.
- **Refresh must always bypass it**, or there is no way to force the truth.
- **A cancelled request must not be retried** — see `START_HERE.md`. Leaving a module cancels its
  in-flight work; a cache must not treat a cancellation as a failed read worth repeating.
- **The Dashboard's Unused tile and the Unused module ask the same question.** They should share one
  cache entry. If they do not, they can disagree on screen, and the headline will be the one that is
  wrong.

## Where to start

`JamfAPIService` is one `ObservableObject` split across extensions. A session cache belongs beside
it — one type, keyed by instance URL and domain, consulted by the fetch methods and cleared by
`RefreshCoordinator` and by Refresh.

Begin with **one domain end to end** — policies, since it is the expensive one — and prove the whole
path before widening. A cache that is right for one domain and wrong for another is worse than none.
