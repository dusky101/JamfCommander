//
//  RefreshCoordinator.swift
//  JamfCommander
//
//  App-wide "data changed" signal. `JamfAPIService` calls `requestRefresh()` from its
//  write chokepoints (every Classic write/delete via `genericRequest`, plus the clone
//  POSTs), so no individual call site can forget to refresh. Dashboards observe `token`
//  and reload when it changes.
//
//  Rapid calls (e.g. a bulk operation issuing many writes) are coalesced via a short
//  debounce into a single bump, so a list reloads once after the burst rather than per
//  write — which also avoids competing with the bulk operation for Jamf's rate limit.
//
//  It also clears `SessionCache`, and does so **immediately** rather than on the debounced
//  bump. The two timings are deliberately different: the bump is a request to reload, and
//  coalescing it is a kindness to Jamf's rate limit; the cache clear is the statement that
//  what is held is no longer true, and delaying that by even 0.6s leaves a window in which
//  switching module would be served data the app itself has just invalidated.
//

import SwiftUI
import Combine

@MainActor
final class RefreshCoordinator: ObservableObject {
    static let shared = RefreshCoordinator()
    private init() {}

    /// Incremented (debounced) whenever Jamf data changes; dashboards observe this.
    @Published private(set) var token: Int = 0

    private var debounceTask: Task<Void, Never>?

    /// Signal that a write succeeded. A burst of calls coalesces into one bump.
    ///
    /// **Main-actor isolated, and deliberately so.** This used to hop — `nonisolated`, hiding a
    /// `Task { @MainActor in … }` — which was harmless while all it did was bump a counter views
    /// observe. It stopped being harmless once it also had to clear `SessionCache`: a write is
    /// routinely followed straight away by a reload (`deletePolicy` then `loadData()`, for one),
    /// and both run on the main actor without suspending in between, so the hopped invalidation
    /// would not have happened yet when the reload consulted the cache. The reload would then be
    /// served the very policy that had just been deleted.
    ///
    /// Isolating it removes the window rather than reasoning about it: a caller already on the main
    /// actor invalidates synchronously, and one that is not must `await`, which suspends it until
    /// the invalidation is done. Either way the cache is clear before the caller continues.
    func requestRefresh() {
        // Before anything else: what the app has cached is now out of date, because the app is what
        // changed it. Every write chokepoint already calls this, so hooking invalidation here means
        // no individual write can forget to invalidate — the same reason the bump itself lives here.
        SessionCache.shared.invalidateAll()
        scheduleBump()
    }

    private func scheduleBump() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s — coalesces write bursts
            guard let self, !Task.isCancelled else { return }
            self.token &+= 1
        }
    }
}
