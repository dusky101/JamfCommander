# Roadmap — per-domain caching

## What

Cache what the app fetches, so opening a module a second time is instant. Refetch only what a change
actually invalidates.

In the maintainer's words: *"could that load cache everything, until a change is made and then the
overlay pops up again with a new message explaining that it's fetching the new data… can the cache
have separate cache files, one for each option. So if a pkg is added then the policies and pkg cache
needs refreshing. If a category was also added then that too. But the profiles and the computers and
blueprints and scripts wouldn't need to be refreshed."*

So: one cache per domain, and a write declares which domains it dirties.

**Updated 19 September 2026**, after the Dashboard grew an Unused tile and he watched the same scan
run twice in a row: *"caching the data once loaded in memory and only updating it if the refresh
button is pressed on window or something is added deleted updated moved. so any update to jamf from
the app makes the data refresh."*

That settles the biggest open question below — **in memory**, not on disk — and names the two things
that invalidate it: **Refresh**, and **any write this app makes**.

## Why

Every module refetches from scratch every time it is opened, because switching module destroys the
previous view and its state. On a tenant of ~250 policies that is 250 hydration calls for the
Dashboard, again for the Unused audit, again for the Packages Deployed tab. It is the single largest
source of waiting in the app, and the reason the launch overlay had to be built at all.

**It got worse on 19 September 2026, and the new case is the clearest one yet.** The Dashboard now
carries an Unused tile, which runs `scanPolicyEstate` — a read of every policy in the tenant — to
count what the audit would list. Clicking **Unused** in the sidebar then runs *the same scan again*,
seconds later, against data that cannot have changed. The maintainer watched exactly that happen and
it is what prompted this update: "it takes ages to load the dashboard but then if i click on unused
it then reloads the data".

There are now four full estate scans available in one session — the Dashboard tile, the Unused
module, the Packages **Deployed** tab, and **Export All** — and nothing stops a session doing all
four with no change in between. A session cache would collapse those to one.

It also costs Jamf. The app is deliberately throttled — batches of 10 with 0.5s gaps — so repeated
scans are not free to the tenant either.

## What it touches

- **Reads:** roughly ten fetch methods across `JamfAPIService` and its extensions would consult the
  cache before going to Jamf.
- **Writes:** roughly fifteen mutating methods would declare what they invalidate. There is already a
  hook — every Classic write funnels through `genericRequest`, which calls
  `RefreshCoordinator.shared.requestRefresh()`. Today that is a single blunt "something changed"
  signal; per-domain invalidation means teaching each write *which* domains it dirtied.
- **UI:** modules would need to distinguish "showing cached data" from "showing fresh data", and the
  launch overlay would need its second message, as described above.

This is not a small change. It is a layer the app does not currently have, threaded through most of
the service.

## Known traps

**1. The cache must be keyed by Jamf instance.** Settings can be pointed at a different tenant, and
the maintainer has both Production and Sandbox environments. A cache that is not keyed by instance URL
will serve one tenant's policies while connected to the other. In an app whose next action might be a
bulk delete, that is not a display bug.

**2. On-disk caching writes tenant data to disk in clear.** The maintainer asked for cache *files*.
Computer inventory carries usernames, email addresses, serial numbers and asset tags; policy names
often describe internal projects. Invariant 4 in `CLAUDE.md` covers credentials, and this is not
credentials — but it is a real decision rather than an implementation detail, and it should be made
deliberately rather than discovered later. Three options, in increasing effort:

- **In memory only**, for the lifetime of the session. Solves the module-switching cost, which is most
  of the pain, and raises no privacy question at all.
- **On disk, in the sandbox container**, keyed by instance. Survives relaunch. Readable by anything
  running as that user.
- **On disk, encrypted**, with the key in the Keychain. Survives relaunch, no plaintext tenant data.

An in-memory cache is a fraction of the work and would deliver most of the benefit. Worth building
first and then seeing whether the on-disk version is still wanted.

**3. Staleness has to be visible.** A cached view that looks identical to a fresh one is how somebody
deletes a policy that was already deleted, or misses one that was added. Whatever is built must say,
on screen, when the data was read.

**4. Invalidation is a correctness problem, not a performance one.** Getting it wrong shows stale data
immediately before a destructive action. The mapping the maintainer sketched is right in spirit —
adding a package dirties packages and policies; adding a category dirties categories and anything
filed under one — but it needs writing down per write method, not inferring.

## Open questions

1. ~~**In memory, or on disk?**~~ **Answered: in memory**, for the lifetime of the session (19
   September 2026). Trap 2 below therefore does not arise — no tenant data is written to disk, and
   no encryption decision is needed. Keep the rest of trap 2 for whoever revisits on-disk caching.
2. ~~**Does the cache survive a relaunch?**~~ **Answered: no**, as a consequence of 1.
3. **Does a write dirty everything, or only its own domains?** His two descriptions differ, and the
   difference is most of the work. The original sketch was per-domain — "if a pkg is added then the
   policies and pkg cache needs refreshing … but the profiles and the computers and blueprints and
   scripts wouldn't need to be refreshed". The newer one is blunt: "any update to jamf from the app
   makes the data refresh". Blunt is a fraction of the effort and never serves something stale;
   per-domain is faster but needs a correct mapping written down per write method. Worth building
   blunt first and measuring whether it is actually slow enough to warrant the mapping.
4. **Is there a maximum age** after which the app refetches regardless — an hour, a day? A tenant can
   be changed by somebody else in the Jamf console, and this app would never know.
5. **What does the second overlay say**, and does it block interaction the way the first one does?
   Blocking on every refetch would be worse than the problem it solves.
6. ~~**Does Refresh always bypass the cache?**~~ **Answered: yes** — it is one of the two things
   named as invalidating the cache.
7. **Does the Dashboard's Unused tile share the module's cache entry, or keep its own?** They ask the
   same question of the same data; they should not be able to disagree on screen.
