//
//  SessionCache.swift
//  JamfCommander
//
//  What this app has already read from Jamf this session, so opening a module a second time does
//  not read the whole tenant again.
//
//  The problem it solves is not abstract. Four different screens read every policy in the tenant —
//  the Dashboard's Unused tile, the Unused module, the Packages "Deployed" tab and Export All — and
//  nothing stopped one session doing all four with no change in between. On a tenant of ~250
//  policies each pass is 250 hydration calls, deliberately paced in batches of 10 with 0.5s gaps.
//  **The pacing is not the problem and is untouched; doing the work four times over is.**
//
//  Three rules govern everything here:
//
//  1. **Keyed by instance.** Settings can be pointed at another tenant mid-session. An entry served
//     across that change would put one tenant's policies in front of an administrator connected to
//     the other, in an app whose next action might be a bulk delete. See `rebase(to:)` — the cache
//     holds one instance's data at a time and *discards* the rest, so the wrong tenant's data is not
//     merely unreachable, it is gone.
//  2. **Two things invalidate: Refresh, and any write this app makes.** Refresh bypasses the cache
//     entirely (the `bypassingCache` parameter on the fetch methods); writes clear it through
//     `RefreshCoordinator`, which every write chokepoint already signals.
//  3. **Staleness is visible.** `readAt` is published so a screen can say when what it is showing
//     was read. A cached list that looks identical to a freshly read one is how somebody deletes a
//     policy that was already gone.
//
//  In memory, for the lifetime of the session. Nothing is written to disk, so no tenant data —
//  computer names, user email addresses, serial numbers, policy names describing internal projects —
//  outlives the process, and there is no encryption decision to get wrong.
//

import SwiftUI
import Combine

// MARK: - What the cache holds

/// A kind of Jamf data, and the unit of **invalidation**.
///
/// Several entries can belong to one domain, and they fall together. That matters: the Dashboard's
/// Unused tile and the Unused module ask the same question of the same data, and if their answers
/// could be invalidated separately they could disagree on screen — where the headline would be the
/// one that is wrong.
enum CacheDomain: String, CaseIterable, Sendable {
    case policies
}

/// One thing the cache holds, and the unit of **lookup**.
///
/// The policies domain is read in two shapes by different screens, so it has two entries. Both are
/// invalidated together, because both are answers about the same policies.
enum CacheEntry: String, CaseIterable, Sendable {
    /// `[Policy]` — `JamfAPIService.fetchPolicies()`. The Policies module, the Dashboard's policy
    /// count, and the computer inspector's policy list.
    case policies
    /// `CachedPolicyEstate` — `JamfAPIService.scanPolicyEstate(knownScriptIDs:)`. The expensive one:
    /// the Unused module, the Dashboard's Unused tile, the Packages "Deployed" tab and Export All.
    case policyEstate

    var domain: CacheDomain {
        switch self {
        case .policies, .policyEstate: .policies
        }
    }
}

// MARK: - The cache

/// The session's read cache. One instance, shared, in memory only.
///
/// Shared rather than owned by `JamfAPIService` for the same reason `RefreshCoordinator` is:
/// `ContentView` creates exactly one service, but the invalidation signal comes from a chokepoint
/// that has no reference to it. Keying by instance URL — rather than by service identity — is what
/// actually makes this safe, and that rule holds however many services exist.
@MainActor
final class SessionCache: ObservableObject {
    static let shared = SessionCache()
    private init() {}

    /// When each entry was last read from Jamf.
    ///
    /// Published so a screen can show it without holding a copy that could drift from the data it
    /// describes. An entry absent here is an entry that is not cached.
    @Published private(set) var readAt: [CacheEntry: Date] = [:]

    /// The Jamf instance every stored entry was read from. Empty means nothing is held.
    private var instanceURL: String = ""

    /// The values themselves. `Any` because the domains differ in type; every read is type-checked
    /// on the way out, and a mismatch is treated as a miss rather than a crash.
    private var values: [CacheEntry: Any] = [:]

    // MARK: - Reading

    /// The cached value for `entry`, or `nil` if it is not held, was read from a different instance,
    /// or is not of the expected type.
    ///
    /// Reading with a different instance URL **discards** what is held — see `rebase(to:)`. A getter
    /// that throws data away is unusual, and it is deliberate: it means no path into this type can
    /// leave another tenant's records sitting in memory.
    func value<T>(_ entry: CacheEntry, as type: T.Type, instanceURL: String) -> T? {
        // Not connected to anything yet: never serve, never store.
        guard !instanceURL.isEmpty else { return nil }
        rebase(to: instanceURL)
        return values[entry] as? T
    }

    // MARK: - Writing

    /// Files a freshly read value under `entry`, and stamps it with the time it was read.
    ///
    /// Callers must not store a read that was cancelled or came back short — see the note on
    /// `JamfAPIService.fetchPolicies(bypassingCache:)`. This type cannot tell a partial answer from
    /// a complete one, so that judgement belongs at the point of the read.
    func store<T>(_ value: T, as entry: CacheEntry, instanceURL: String) {
        guard !instanceURL.isEmpty else { return }
        rebase(to: instanceURL)
        values[entry] = value
        readAt[entry] = Date()
    }

    // MARK: - Invalidation

    /// Drops every entry in a domain. Called when a write dirties that domain.
    func invalidate(_ domain: CacheDomain) {
        for entry in CacheEntry.allCases where entry.domain == domain {
            values.removeValue(forKey: entry)
            readAt.removeValue(forKey: entry)
        }
    }

    /// Drops everything.
    ///
    /// The blunt rule the maintainer settled on: *"any update to jamf from the app makes the data
    /// refresh"*. Writes are rare next to module switches, and module switches are what hurts, so
    /// this costs almost nothing and can never serve something stale. A per-write domain mapping is
    /// faster and is a correctness problem if it is wrong; it is not worth that risk until this is
    /// measurably too slow.
    func invalidateAll() {
        values.removeAll()
        readAt.removeAll()
    }

    /// Discards everything and forgets which instance it belonged to.
    ///
    /// Called when the app authenticates, so a reconnection never serves what was read before it.
    func reset() {
        invalidateAll()
        instanceURL = ""
    }

    // MARK: - The instance rule

    /// Points the cache at an instance, discarding everything held if it is a different one.
    ///
    /// **This is the load-bearing line in this file.** The maintainer runs both a Production and a
    /// Sandbox tenant and can repoint Settings at either without relaunching. A cache that merely
    /// *keyed* entries by URL would still be holding the other tenant's policies; this discards
    /// them, so there is nothing to serve by mistake.
    private func rebase(to instanceURL: String) {
        guard instanceURL != self.instanceURL else { return }
        if !self.instanceURL.isEmpty {
            // The one thing this type does that has no visible consequence on screen — every other
            // change shows up as a stamp appearing or vanishing. Neither URL is logged: an instance
            // URL identifies the tenant and is never written to the console (root `CLAUDE.md`,
            // invariant 4).
            print("[Cache] Instance changed — cached data discarded")
        }
        values.removeAll()
        readAt.removeAll()
        self.instanceURL = instanceURL
    }
}
