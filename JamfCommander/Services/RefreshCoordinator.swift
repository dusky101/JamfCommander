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

import SwiftUI
import Combine

@MainActor
final class RefreshCoordinator: ObservableObject {
    static let shared = RefreshCoordinator()
    private init() {}

    /// Incremented (debounced) whenever Jamf data changes; dashboards observe this.
    @Published private(set) var token: Int = 0

    private var debounceTask: Task<Void, Never>?

    /// Signal that a write succeeded. Safe to call from any actor/thread — the published
    /// change is delivered on the main actor, and a burst of calls coalesces into one bump.
    nonisolated func requestRefresh() {
        Task { @MainActor in
            self.scheduleBump()
        }
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
