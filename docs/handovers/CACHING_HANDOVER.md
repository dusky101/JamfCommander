# Handover — per-domain caching

**State at handover:** 19 September 2026, app version 9.0. **Phases 1 and 2 are written and build.**
Phase 1 (policies only) has been run once by the maintainer; phase 2 (every other domain, plus the
Live/Cached setting) has not.

Read `docs/roadmap/CACHING.md` first — it holds the intent and the maintainer's own words. This file
holds what is true about the code today.

---

## Proven — and what is NOT

| Proven against a live tenant | Built and compiles, but unproven |
| --- | --- |
| **The estate scan is cached and shared.** On a 249-policy tenant, Dashboard → Unused → Dashboard printed `[Packages] Estate scan:` **once**. Before, that was three scans. | Every other domain's cache (phase 2) |
| **Phase 1 alone did not make the Unused module feel faster** — because it waits on four reads and only one was cached. See below. | The Live/Cached switch, and the Refresh Data button |
| | Refresh bypassing the cache on any module |
| | A write clearing the cache and the next read going to Jamf |
| | The "Read … ago" stamp appearing, and being right |
| | A cancelled or incomplete scan **not** being cached |
| | **Anything to do with a second tenant** — the maintainer has one instance today. Multiple tenants are future work (`docs/roadmap/MULTIPLE_ENVIRONMENTS.md`), and the instance-keying here is written for it but cannot be exercised yet. |

`xcodebuild -scheme JamfCommander -destination "platform=macOS" clean build` succeeds with **no
Swift warnings**. There is no test target, so nothing else is exercised automatically. **"It builds"
is not "it works"** — and this is a cache in front of destructive actions, so the distinction
matters more here than usual.

## Why phase 1 looked like it had failed

The maintainer ran it and reported the Unused module still loading rather than appearing instantly.
The cache was working; the module simply does not wait on the estate alone:

```
RedundantDashboardView.load()
  fetchInstallomatorScriptIDs()   → fetchScripts()      ← uncached in phase 1
  scanPolicyEstate()                                    ← cached ✓
  fetchProfiles()                                       ← uncached, and a detail call per profile
  fetchJamfPackages()                                   ← uncached
  fetchCategories()                                     ← uncached
```

`fetchProfiles` is the second most expensive read in the app — it hydrates every profile
individually — so four of the five reads still went to Jamf and the screen took about as long as
before. **A cache that covers one read of a screen that makes five is invisible.** That is the whole
lesson of phase 1, and it is why phase 2 widened to every domain rather than adding them one at a
time.

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

## Phase 2 — every domain, and the Live/Cached setting

### Everything now cached

| Entry | Method | Domain |
| --- | --- | --- |
| `.policies` | `fetchPolicies` | policies |
| `.policyEstate` | `scanPolicyEstate` | policies |
| `.profiles` | `fetchProfiles` | profiles |
| `.computers` | `fetchComputers` | computers |
| `.dashboardComputers` | `fetchDashboardComputers` | computers |
| `.scripts` | `fetchScripts` | scripts |
| `.packages` | `fetchJamfPackages` | packages |
| `.categories` | `fetchCategories` | categories |
| `.computerGroups` | `fetchComputerGroups` | groups |
| `.installomatorScan` | `fetchInstallomatorPolicies` | installomator |
| `.installomatorLabels` | Installomator's GitHub label list | installomator |
| `.buildings` / `.departments` | `fetchBuildings` / `fetchDepartments` | userLocation |

`fetchInstallomatorScriptIDs()` needed no entry — it filters `fetchScripts()`, so caching that made
it free everywhere it is called, which is every screen that widens Installomator detection.

`.computers` and `.dashboardComputers` are separate entries because they are different reads
returning different types; they share one domain and fall together.

**The Dashboard now primes everything the Unused module needs.** All five of that module's reads are
cache hits on a second visit.

### Blueprints are deliberately excluded

They come from the Platform API Gateway — a different host with credentials set separately in
Settings — so the Jamf Pro instance URL the cache rebases on says nothing about which Platform tenant
a blueprint came from. Changing only the Platform credentials would not rebase the cache and it would
serve the previous tenant's blueprints. One list read is not worth that hole. It stays live until the
cache can key Platform data by its own identity.

### Live or Cached — Settings → General

A segmented **Live / Cached** control, and beneath it, in Cached mode only, a **Refresh Data** button.

- **Cached is the default.** Reading the whole tenant again on every module switch is the app's
  largest source of waiting, and the switch is there for anyone who would rather pay that cost.
- **Live holds nothing at all** rather than holding it and declining to serve it — `store` refuses in
  Live mode, and switching to Live discards what is already held. Choosing Live should not leave the
  tenant's records in memory, served again the moment the switch goes back.
- The setting lives in `UserDefaults` under `SessionCache.cachingEnabledKey`, whose default is
  registered by `SessionCache.init()` so the switch and the cache cannot disagree about it.
- **Refresh Data** sends the same signal a write sends: discard everything, and ask whatever module
  is on screen to reload. It is disabled when nothing is held.

### Two things phase 2 had to change to be correct

**The Dashboard now observes `RefreshCoordinator.token`**, so Refresh Data works while looking at it.
But its own category actions already refresh it the instant they finish, and the signal they send
arrives 0.6s later debounced — so that observer would have reloaded the Dashboard twice for one
change. It therefore refreshes **quietly** (`refreshDashboard(showingLoadingState: false)`): the tiles
keep their figures until new ones arrive. Replacing a Dashboard somebody is reading with a
full-screen spinner because a write finished elsewhere is worse than letting the numbers change.

**`ProfileDashboardView.refreshAction` now takes a `Bool`.** The two reasons to refresh want
different things: the Refresh button must go to Jamf whatever is held, while a reload after a write
follows an invalidation and can read normally.

### A compiler detail worth knowing before touching this

The obvious helper — `cachedRead(entry, bypassingCache:) { try await genericFetch(…) }` — **does not
work here** and was written, tried and removed. Wrapping a `genericFetch` in a closure moves the
decode into a context the compiler treats as concurrent, and every response type in this module has a
main-actor-isolated `Decodable` conformance (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). It produced
nine `#IsolatedConformances` warnings — *"an error in the Swift 6 language mode"* — and annotating
the closure `@MainActor` did not clear them. The shape that works is two plain calls, `cachedValue`
then `storeInCache`, three lines per read and no closure. Don't reintroduce the tidier version.

## What was deliberately not done

- **Blueprints**, for the reason above.
- **No max age.** The maintainer named exactly two invalidators — Refresh and any write — and age is
  not one of them. The consequence is real and unresolved: leave the app open all day, let somebody
  else change Jamf in the console, and the app will not know. The visible stamp is the mitigation,
  and it is why he asked for it.
- **No in-flight coalescing.** Two concurrent readers of the same uncached domain both scan, exactly
  as today. No current screen does this, so adding it would have been speculative.
- **No second overlay.** `CACHING.md` open question 5 asked what it says and whether it blocks; the
  phase 1 brief replaced it with the on-screen stamp, which does not block anything.

## Export All — decided

**It reads from the cache, and asks first.** It is one of the four scans the maintainer named, so
excluding it would have missed a quarter of the point — but a CSV leaves the app carrying no record
of when it was true, and the reader cannot tell. Everywhere else the app shows staleness on screen
next to a Refresh button; this is the one place it cannot, so it asks beforehand instead.

`ExportFreshnessPrompt` appears when the ZIP would be built from data already held, naming how old
that data is. Two answers, no third — Escape and the window's own dismissal already cancel, and a
third button would bury the common answer.

- **No, Use Current Data** — exports what is held.
- **Yes, Refresh First** — the prompt swaps to a "Refreshing data…" state, `refreshForExport()`
  discards everything and re-reads what the export leans on hardest, and the export starts when it
  finishes. Nothing is read twice: the export then finds those reads in the cache. Buildings and
  departments are not primed and are simply read by the computers sheet as it always was.

In **Live** mode the prompt never appears — nothing is held, so the export reads from Jamf anyway
and there is nothing to ask about.

The export sheet is raised from the prompt sheet's `onDismiss`, not from its buttons. Presenting one
sheet while another is still on screen does not reliably work on macOS, which is what the
`exportOncePromptCloses` flag is for.

## What to look at, in order

1. **Dashboard, then Unused.** Unused should now appear near-instantly — all five of its reads are
   cache hits. "Read … ago" sits beside its Refresh button, and under the Dashboard's tiles.
2. **Back to the Dashboard.** No `[Installomator] Parsed 1268 …` a second time, and no second
   `[Packages] Estate scan:`.
3. **Refresh on any module.** The stamp resets; the console shows the read actually happening.
4. **Delete a policy, or move one to a category.** The list must come back *without* it. If it comes
   back with it, the `requestRefresh()` isolation fix is not actually closed.
5. **Settings → General.** Switch to **Live** — every module should read from Jamf again on every
   visit, and the stamps should vanish. Switch back to **Cached**, then use **Refresh Data**: the
   held-data count drops to nothing and the module on screen reloads.
6. **Add or rename a category on the Dashboard.** It should reload **once**, not twice, and should
   not flash the full-screen spinner a second time.
7. **Export All.** The prompt should name how old the data is. **No** exports straight away; **Yes**
   shows "Refreshing data…" and then starts the export on its own. In Live mode neither happens —
   the export begins immediately.

## Where this goes next

- **Blueprints**, once Platform data can be keyed by its own identity.
- **A max age**, if the maintainer decides one is wanted.
- **Multiple tenants** (`docs/roadmap/MULTIPLE_ENVIRONMENTS.md`). The instance-keying is already
  written for it: `SessionCache.rebase(to:)` discards everything when the Jamf Pro URL changes, so
  one tenant's records can never be served to another. It has never been exercised, because there is
  only one tenant today.
