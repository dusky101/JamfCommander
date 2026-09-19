# Roadmap — caching

**Mostly built, 20 September 2026.** A session cache now covers every Jamf Pro read: in memory,
keyed by instance URL, cleared by the Refresh button and by any write the app makes, with a
"Read … ago" stamp wherever a module can be showing held data, and a **Live / Cached** switch in
Settings → General for anyone who would rather always read live.

`docs/handovers/CACHING_HANDOVER.md` is the account of what was built, what is proven against the
tenant and what is not. **This file is now only what remains undone** — the original entry has been
trimmed, because the parts it described are in the code and a stale entry that still reads as
current is worse than none.

---

## 1. Blueprints are not cached

They come from the Jamf **Platform API Gateway** — a different host, with credentials set separately
in Settings. The cache rebases on the Jamf Pro instance URL, which says nothing about which Platform
tenant a blueprint came from, so changing only the Platform credentials would leave the previous
tenant's blueprints being served.

**What it needs:** Platform data keyed by its own identity rather than by the Jamf Pro URL. Until
then one list read per Dashboard visit is the price, which is small.

## 2. No maximum age

The two things that invalidate are Refresh and any write **this app** makes. A tenant changed by
somebody else in the Jamf console is invisible to it: leave the app open all day and it will still
be showing this morning's estate.

The visible stamp is the mitigation and the reason it was asked for — but whether an hour, or a day,
should force a re-read regardless is **still undecided**. It was never answered, rather than
answered "no".

## 3. Invalidation is blunt, not per-domain

Any write clears everything. The maintainer's original sketch was per-domain — *"if a pkg is added
then the policies and pkg cache needs refreshing … but the profiles and the computers and blueprints
and scripts wouldn't need to be refreshed"* — and `CacheDomain` exists so that mapping can be written
later without restructuring anything.

Blunt was built first deliberately: it can never serve something stale, and writes are rare next to
module switches. **Only worth revisiting if a write is measurably slow to recover from in practice.**
Getting a per-domain mapping wrong shows stale data immediately before a destructive action, which
is a correctness bug rather than a performance one.

## 4. On disk, if it is ever wanted

Settled as **in memory only**, which is why no tenant data is written anywhere and no encryption
decision was needed. If surviving a relaunch is ever worth it, the decision that was avoided comes
back with it:

- **In the sandbox container**, keyed by instance. Readable by anything running as that user.
- **Encrypted**, with the key in the Keychain. No plaintext tenant data.

Not a detail to discover later: computer inventory carries usernames, email addresses, serial
numbers and asset tags, and policy names often describe internal projects.

## 5. The instance keying has never been exercised

`SessionCache.rebase(to:)` discards everything when the Jamf Pro URL changes, so one tenant's
records cannot be served to another. It is written for `docs/roadmap/MULTIPLE_ENVIRONMENTS.md` and
**has never run against a second tenant, because there is only one today.** Whoever adds multiple
environments should treat it as unproven code, not as a feature already in place.
