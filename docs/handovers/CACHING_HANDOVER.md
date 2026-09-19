# Handover — per-domain caching

**State at handover:** 19 September 2026, app version 9.0. **Phase 1 is written and builds. Nothing
in it has been run against a tenant yet** — the proven column below is empty, and it stays empty
until the maintainer has used it and said what he saw.

Read `docs/roadmap/CACHING.md` first — it holds the intent and the maintainer's own words. This file
holds what is true about the code today.

---

## Proven — and what is NOT

| Proven against a live tenant | Built and compiles, but unproven |
| --- | --- |
| *(nothing yet)* | The cache serves a second read of the policies domain |
| | The Dashboard → Unused path runs **one** estate scan instead of two |
| | Refresh bypasses the cache on Policies, Unused and Packages |
| | A write clears the cache and the next read goes to Jamf |
| | The "Read … ago" stamp appears, and is correct |
| | Switching Settings to the other tenant discards the first tenant's data |
| | A cancelled or incomplete scan is **not** cached |

The build is the only thing actually verified: `xcodebuild -scheme JamfCommander -destination
"platform=macOS" clean build` succeeds with **no Swift warnings**. There is no test target, so
nothing else has been exercised automatically. **"It builds" is not "it works"** — and this is a
cache in front of destructive actions, so the distinction matters more here than usual.

## What phase 1 built

Two new files, and changes threaded through the policies read and write paths.

### `Services/SessionCache.swift` — the cache

In memory, session lifetime, nothing on disk. Three rules, in the order they matter:

1. **One instance at a time.** `rebase(to:)` discards everything the moment it is touched with a
   different instance URL. This is stronger than keying entries by URL: the other tenant's data is
   not merely unreachable, it is *gone*, so there is nothing to serve by mistake. A rebase prints
   `[Cache] Instance changed — cached data discarded` — without either URL, because an instance URL
   identifies the tenant and is never logged.
2. **`CacheDomain` is the unit of invalidation; `CacheEntry` is the unit of lookup.** The policies
   domain holds two entries — `.policies` (`fetchPolicies`) and `.policyEstate` (`scanPolicyEstate`)
   — and they fall together. That is deliberate: the Dashboard's Unused tile and the Unused module
   read the same estate, and entries that could be invalidated separately could disagree on screen.
3. **`readAt` is `@Published`**, so a screen can say when what it shows was read.

### `SharedUI/DataFreshnessLabel.swift` — the visible half

"Read 3 min ago", live (SwiftUI keeps a `.relative` date running), with the absolute time in the
tooltip. Added to `FilterBar` behind a new optional `readAt:` parameter — `nil` shows nothing, which
is the honest answer for a module whose data is not cached yet. Wired up on **Policies** and
**Unused**.

The wording is "Read", not "Updated": nothing was updated. It says when the app last asked Jamf,
which is the only claim it can honestly make — the tenant may have been changed in the console since.

### Reads that now consult the cache

Both gained a `bypassingCache: Bool = false` parameter, so existing call sites are unchanged and
only Refresh passes `true`:

| Method | Entry | Read by |
| --- | --- | --- |
| `fetchPolicies(bypassingCache:)` | `.policies` | Policies module, Dashboard policy count, computer inspector |
| `scanPolicyEstate(knownScriptIDs:bypassingCache:onPolicy:)` | `.policyEstate` | Unused module, Dashboard Unused tile, Packages **Deployed**, Export All |

**A cached estate is only served when `knownScriptIDs` match** the set the cached scan was built
with — the scan's `installomator` list depends on them. Every caller derives them the same way
today, so the check costs nothing; it is there so a future caller passing a different set gets a
miss rather than an answer to somebody else's question.

**`onPolicy` is not replayed for a cached scan.** There is nothing to watch climb when the answer is
already in hand, and 250 callbacks hopping to the main actor would be slower than showing the total.

### Two traps that were closed, and would have been bugs

**1. A cancelled scan returns successfully.** Both reads skip a policy they cannot hydrate rather
than failing the whole pass — so a cancelled read comes back *short*, without throwing. The
Dashboard's Unused tile is *designed* to be cancelled (it starts after the tiles are up; leaving the
module abandons it), so this is the common case, not the edge case. Caching it would have made the
first half of an abandoned scan the session's answer to "what is unused".

Both now cache only when `!Task.isCancelled` **and** the number of policies read equals the number
in the list response. An incomplete scan prints `[Packages] Estate scan incomplete — not cached`.

*Consequence worth knowing:* on a tenant where one policy reliably fails to hydrate, the estate
would never be cached and the feature would silently do nothing. The stamp is how you would notice —
it would never appear on Unused.

**2. `RefreshCoordinator.requestRefresh()` used to hop, and could not any more.** It was
`nonisolated`, hiding a `Task { @MainActor in … }`. Harmless while it only bumped a counter; not
harmless once it also had to clear the cache. A write is routinely followed straight away by a
reload — `PoliciesDashboardView.deletePolicy` does `await api.deletePolicy(id:)` then
`await loadData()` — and both run on the main actor **without suspending in between**, so the hopped
invalidation would not have happened yet when the reload consulted the cache. The reload would have
been served the policy that had just been deleted.

It is now `@MainActor`. A caller already there invalidates synchronously; one that is not must
`await`, which suspends it until the invalidation is done. Either way the cache is clear before the
caller continues. **This is the single most important line of the phase and it is invisible on
screen** — it can only be proven by deleting something and watching the list.

### Writes that were silent, and are not any more

The previous handover said to check whether the Pro API writes signal. **Five did not**, and all of
them create or destroy real objects:

| File | Method | What it does |
| --- | --- | --- |
| `+Packages.swift` | `createInstallomatorPolicyAsync` | creates a policy |
| `+PackageUpload.swift` | `createPackageRecord` | creates a package record |
| `+PackageUpload.swift` | `deletePackageRecord` | deletes a package record |
| `+PackageUpload.swift` | `uploadPackageFile` | changes the record's transfer status |
| `+PackageUpload.swift` | `createInstallPolicy` | creates a policy |

Each now calls `RefreshCoordinator.shared.requestRefresh()`. The two policy-creation paths and the
package-record creation signal **before** parsing the id back, because the object exists in Jamf
whether or not the app can read its id.

This was not scope creep: "any write invalidates" is the requirement, and a write that does not
signal is a cache that goes stale silently — the failure mode that matters.

## What was deliberately not done

- **Only the policies domain.** Profiles, computers, scripts, packages, categories and blueprints
  still read from Jamf every time. Widening is mechanical once this one is proven; doing it first
  would have meant proving seven paths at once.
- **No max age.** The maintainer named exactly two invalidators — Refresh and any write — and age is
  not one of them. The consequence is real and unresolved: leave the app open all day, let somebody
  else change Jamf in the console, and the app will not know. The visible stamp is the mitigation,
  and it is why he asked for it.
- **No in-flight coalescing.** Two concurrent readers of the same uncached domain both scan, exactly
  as today. No current screen does this, so adding it would have been speculative.
- **No second overlay.** `CACHING.md` open question 5 asked what it says and whether it blocks; the
  phase 1 brief replaced it with the on-screen stamp, which does not block anything.

## One judgement call that is the maintainer's, not mine

**Export All reads from the cache.** It is one of the four scans he named, so leaving it out would
have missed a quarter of the point. But a CSV outlives the session and carries no "read at" stamp,
so the staleness rule — *it must say on screen when the data was read* — does not follow the file out
of the app. Either stamp the exports, or make Export All bypass the cache. His call.

## What to look at, in order

1. **Dashboard, then Unused.** The console should print `[Packages] Estate scan:` **once**, not
   twice. Unused should appear more or less instantly, with "Read … ago" beside its Refresh button.
   This is the complaint that started all of this.
2. **Policies, away, back.** Instant the second time, with a stamp whose age keeps climbing.
3. **Refresh on Policies.** The stamp resets to "0 sec"; a scan runs.
4. **Delete a policy, or move one to a category.** The list must come back *without* it. If it comes
   back with it, trap 2 above is not actually closed.
5. **Settings → the other tenant → reconnect.** `[Cache] Instance changed — cached data discarded`,
   and every count belongs to the tenant now connected. **Nothing else in this phase matters if this
   one is wrong.**
6. **Packages → Deployed, then Unused** (or the reverse). One scan between them.

## Where this goes next

Widening is one entry per domain and one `bypassingCache` parameter per fetch method — the shape is
set. Blueprints is the exception worth thinking about separately: it is the Platform API with its own
credentials and its own host, so "keyed by instance URL" means a *different* URL, and it should not
share the Jamf Pro instance's key.
