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

## Why

Every module refetches from scratch every time it is opened, because switching module destroys the
previous view and its state. On a tenant of ~250 policies that is 250 hydration calls for the
Dashboard, again for the Unused audit, again for the Packages Deployed tab. It is the single largest
source of waiting in the app, and the reason the launch overlay had to be built at all.

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

1. **In memory, or on disk?** See trap 2. This decision sets the size of the work.
2. **Does the cache survive a relaunch?** Only meaningful if on disk.
3. **Is there a maximum age** after which the app refetches regardless — an hour, a day? A tenant can
   be changed by somebody else in the Jamf console, and this app would never know.
4. **What does the second overlay say**, and does it block interaction the way the first one does?
   Blocking on every refetch would be worse than the problem it solves.
5. **Does Refresh always bypass the cache?** It should, or there is no way to force the truth.
