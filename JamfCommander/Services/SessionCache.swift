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
/// **Blueprints are deliberately absent.** They come from the Jamf Platform API Gateway — a
/// different host, with its own credentials set separately in Settings — so the Jamf Pro instance
/// URL this cache rebases on says nothing about which Platform tenant a blueprint came from.
/// Changing only the Platform credentials would not rebase the cache, and it would serve the
/// previous tenant's blueprints. One list read is not worth that hole; it stays live until the
/// cache can key Platform data by its own identity.
enum CacheDomain: String, CaseIterable, Sendable {
    case policies
    case profiles
    case computers
    case scripts
    case packages
    case categories
    case groups
    case installomator
    case userLocation
}

/// One thing the cache holds, and the unit of **lookup**.
///
/// The policies domain is read in two shapes by different screens, so it has two entries. Both are
/// invalidated together, because both are answers about the same policies.
enum CacheEntry: String, CaseIterable, Sendable {
    /// `[Policy]` — `fetchPolicies()`. Policies module, Dashboard count, computer inspector.
    case policies
    /// `CachedPolicyEstate` — `scanPolicyEstate(knownScriptIDs:)`. The most expensive read in the
    /// app: the Unused module, the Dashboard's Unused tile, Packages **Deployed**, Export All.
    case policyEstate
    /// `[ConfigProfile]` — `fetchProfiles()`. Hydrates every profile with a detail call, so it is
    /// the second most expensive read, and the Unused module waits on it as well as on the estate.
    case profiles
    /// `[ComputerInventoryRecord]` — `fetchComputers()`. The Computers module.
    case computers
    /// `[BasicComputerRecord]` — `fetchDashboardComputers()`. A lighter read than `.computers` and
    /// a different type, so it is a separate entry; both are invalidated together.
    case dashboardComputers
    /// `[ScriptRecord]` — `fetchScripts()`. Also what `fetchInstallomatorScriptIDs()` filters, so
    /// caching this makes that free everywhere it is called.
    case scripts
    /// `[JamfPackage]` — `fetchJamfPackages()`.
    case packages
    /// `[Category]` — `fetchCategories()`. Read by nearly every module for its filter chips.
    case categories
    /// `[ComputerGroup]` — `fetchComputerGroups()`. The scope pickers.
    case computerGroups
    /// `[String]` — Installomator's published label list. From GitHub, not Jamf.
    case installomatorLabels
    /// `[String: String]` — `fetchBuildings()`.
    case buildings
    /// `[String: String]` — `fetchDepartments()`.
    case departments

    var domain: CacheDomain {
        switch self {
        case .policies, .policyEstate: .policies
        case .profiles: .profiles
        case .computers, .dashboardComputers: .computers
        case .scripts: .scripts
        case .packages: .packages
        case .categories: .categories
        case .computerGroups: .groups
        case .installomatorLabels: .installomator
        case .buildings, .departments: .userLocation
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

    private init() {
        // So `@AppStorage("dataCacheEnabled") var x = true` in Settings and `UserDefaults.bool`
        // here agree about the default. Without registering it, an unset key reads as `false` on
        // this side and `true` on that one, and the switch would lie about its own state.
        UserDefaults.standard.register(defaults: [Self.cachingEnabledKey: true])
    }

    // MARK: - Live or Cached

    /// The Settings key behind the **Live / Cached** switch in Settings → General.
    ///
    /// Owned here rather than by the view, because this is the type whose behaviour it changes and
    /// the default has to be registered alongside it.
    static let cachingEnabledKey = "dataCacheEnabled"

    /// Whether the app is in **Cached** mode. `false` is **Live**: every read goes to Jamf, exactly
    /// as the app behaved before any of this existed.
    ///
    /// Read from `UserDefaults` on each call rather than held, so flipping the switch takes effect
    /// on the next read with nothing to keep in sync.
    var isCaching: Bool {
        UserDefaults.standard.bool(forKey: Self.cachingEnabledKey)
    }

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
        // Live mode: there is nothing to serve, by choice.
        guard isCaching else { return nil }
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
        // Live mode holds nothing at all, rather than holding it and declining to serve it. Someone
        // who has chosen Live should not have the tenant's records sitting in memory regardless.
        guard isCaching, !instanceURL.isEmpty else { return }
        rebase(to: instanceURL)
        values[entry] = value
        readAt[entry] = Date()
    }

    // MARK: - The scan already running

    /// The estate scan currently in flight, if there is one, and the script ids it was started with.
    ///
    /// Two separate problems, one answer.
    ///
    /// **A scan nobody waits for used to be thrown away.** The Dashboard starts its estate scan
    /// *after* the tiles are on screen, so the Dashboard looks finished while the Unused tile is
    /// still counting. Clicking away cancelled it — on a 249-policy tenant, 110 policies read and
    /// discarded — and the next module started from nothing. That was the right behaviour before
    /// there was a cache, and the comment in `DashboardView` still said so: an abandoned scan was
    /// waste. It is not waste any more; it fills the cache for every other module. The task below
    /// is therefore **unstructured**, so it outlives the view that asked for it and runs to
    /// completion.
    ///
    /// **Two modules used to be able to scan at once.** With the first problem fixed they would:
    /// the Dashboard's scan would still be running when the next module asked for one. A second
    /// caller now waits for the first instead of starting its own — which is also the only polite
    /// thing to do to a tenant that is deliberately read in batches of 10.
    private(set) var runningEstateScan: (task: Task<PolicyEstateScan, Error>, knownScriptIDs: Set<String>)?

    /// Whether an estate scan is in flight, published so the UI can say so.
    ///
    /// Separate from `runningEstateScan` because that carries a `Task`, which is not something a
    /// view should be handed. This is the only part of it a view has any business knowing.
    @Published private(set) var isScanningEstate = false

    /// Registers the scan now running, so anything else that asks can wait for it.
    func setRunningEstateScan(_ task: Task<PolicyEstateScan, Error>?, knownScriptIDs: Set<String>) {
        if let task {
            runningEstateScan = (task, knownScriptIDs)
        } else {
            runningEstateScan = nil
        }
        isScanningEstate = runningEstateScan != nil
    }

    /// Clears the record of a running scan, but only if it is still the one named.
    ///
    /// A Refresh pressed mid-scan starts a second and registers it; the first must not then wipe
    /// that registration as it finishes, or the next caller would start a third.
    func clearRunningEstateScan(ifCurrent task: Task<PolicyEstateScan, Error>) {
        if runningEstateScan?.task == task {
            runningEstateScan = nil
            isScanningEstate = false
        }
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

// MARK: - How a read consults the cache

extension JamfAPIService {

    /// The cached value for `entry`, or `nil` — because nothing is held, because this is a Refresh,
    /// or because the app is in Live mode.
    ///
    /// Deliberately two calls (this and `storeInCache`) rather than one helper taking a closure.
    /// A closure would read better, but wrapping a `genericFetch` in one moves the decode into a
    /// context the compiler treats as concurrent, and every response type in this module has a
    /// main-actor-isolated `Decodable` conformance — a warning today and an error in the Swift 6
    /// language mode. Three plain lines per read cost less than working around that.
    func cachedValue<T>(_ entry: CacheEntry, as type: T.Type, bypassingCache: Bool) -> T? {
        guard !bypassingCache else { return nil }
        return SessionCache.shared.value(entry, as: type, instanceURL: baseURL)
    }

    /// Files a freshly read value, unless the read was cancelled.
    ///
    /// Leaving a module cancels its in-flight work, and whatever a cancelled read returned is not
    /// an answer worth keeping for the rest of the session. A read that can come back *short*
    /// without throwing — `fetchPolicies`, `scanPolicyEstate`, `fetchInstallomatorPolicies` all
    /// skip an item they cannot hydrate rather than failing the pass — must check its own
    /// completeness as well; those three do, in full, at their own call sites.
    func storeInCache<T>(_ value: T, as entry: CacheEntry) {
        guard !Task.isCancelled else { return }
        SessionCache.shared.store(value, as: entry, instanceURL: baseURL)
    }
}
