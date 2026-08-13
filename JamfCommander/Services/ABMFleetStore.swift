//
//  ABMFleetStore.swift
//  JamfCommander
//
//  The Apple Business Manager fleet as the views see it.
//

import Foundation
import Combine

/// Holds the cached Apple Business Manager fleet and drives refreshes.
///
/// Views read `record(for:)` — a dictionary lookup, never a network call. The Computers table renders
/// a row per Mac and must not trigger a request per row.
final class ABMFleetStore: ObservableObject {

    static let shared = ABMFleetStore()

    /// Keyed by serial number, which is the only identifier Jamf and ABM share.
    @Published private(set) var recordsBySerial: [String: ABMDeviceRecord] = [:]
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var progress: RefreshProgress?
    @Published private(set) var lastError: String?
    @Published private(set) var lastSummary: Summary?
    /// True when the cache is older than its lifetime, or when there is no cache at all.
    @Published private(set) var isStale = true

    struct RefreshProgress: Equatable {
        let completed: Int
        let total: Int

        var fraction: Double {
            guard total > 0 else { return 0 }
            return Double(completed) / Double(total)
        }
    }

    /// What the last refresh found. Mirrors the proof-of-concept extract's summary so the two can be
    /// compared directly.
    struct Summary: Equatable {
        let macCount: Int
        let outOfWarranty: Int
        let noWarrantyRecord: Int
        /// Devices retrieved, but whose warranty request failed after every retry. Counted separately
        /// from `noWarrantyRecord`: one is a device Apple holds no cover for, the other is data we
        /// simply do not have. Without this line a run reports its full total with silent holes in it.
        let warrantyUnavailable: Int
        let inferredPurchaseDates: Int
        let missingPurchaseDates: Int
        let nonMacCount: Int
        let failedCount: Int
        /// Why most of the failures happened. Without this a partial run is unactionable.
        let failureReason: String?
    }

    private init() {}

    // MARK: - Reading

    /// The ABM record for a serial, or `nil` when ABM has none — which the UI must present as "not in
    /// Apple Business Manager", distinct from "no warranty record".
    func record(for serialNumber: String?) -> ABMDeviceRecord? {
        guard let serialNumber, !serialNumber.isEmpty else { return nil }
        return recordsBySerial[serialNumber]
    }

    var isConfigured: Bool {
        ABMAPIService.shared.isConfigured && !configuredServerId.isEmpty
    }

    private var configuredServerId: String {
        UserDefaults.standard.string(forKey: "abmMDMServerId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Cache

    /// Loads whatever is cached without touching the network. Safe to call on view appearance.
    func loadFromCache() async {
        let serverId = configuredServerId
        guard !serverId.isEmpty else {
            apply(records: [], refreshedAt: nil, isStale: true)
            return
        }

        guard let snapshot = await ABMCache.shared.snapshot(forServer: serverId) else {
            apply(records: [], refreshedAt: nil, isStale: true)
            return
        }

        apply(
            records: snapshot.records,
            refreshedAt: snapshot.refreshedAt,
            isStale: snapshot.isStale()
        )
    }

    // MARK: - Refresh

    /// Fetches the whole fleet from Apple Business Manager and replaces the cache.
    ///
    /// Ignores the cache lifetime — this is the explicit refresh. Concurrent calls are ignored rather
    /// than queued, so a double click does not run two full fetches.
    func refresh() async {
        guard !isRefreshing else { return }

        let serverId = configuredServerId
        guard ABMAPIService.shared.isConfigured else {
            lastError = ABMAPIService.ABMError.notConfigured.localizedDescription
            return
        }
        guard !serverId.isEmpty else {
            lastError = "No MDM Server ID is set. Run Test Connection to list the servers in your organisation."
            return
        }

        isRefreshing = true
        lastError = nil
        progress = RefreshProgress(completed: 0, total: 0)

        do {
            let result = try await ABMAPIService.shared.fetchFleet(mdmServerId: serverId) { completed, total in
                self.progress = RefreshProgress(completed: completed, total: total)
            }

            let refreshed = Date()
            let snapshot = ABMCache.Snapshot(
                records: result.records,
                refreshedAt: refreshed,
                mdmServerId: serverId
            )

            // A cache write failure is worth reporting but must not discard data already fetched.
            do {
                try await ABMCache.shared.store(snapshot)
            } catch {
                lastError = "Fetched \(result.records.count) devices, but the cache could not be saved: \(error.localizedDescription)"
            }

            apply(records: result.records, refreshedAt: refreshed, isStale: false)
            lastSummary = Self.summarise(result)
        } catch {
            lastError = error.localizedDescription
        }

        progress = nil
        isRefreshing = false
    }

    /// Discards the cache and everything in memory. Used when the ABM credentials are cleared.
    func clear() async {
        await ABMCache.shared.clear()
        apply(records: [], refreshedAt: nil, isStale: true)
        lastSummary = nil
        lastError = nil
    }

    // MARK: - Helpers

    private func apply(records: [ABMDeviceRecord], refreshedAt: Date?, isStale: Bool) {
        recordsBySerial = Dictionary(records.map { ($0.serialNumber, $0) }, uniquingKeysWith: { first, _ in first })
        self.refreshedAt = refreshedAt
        self.isStale = isStale
    }

    private static func summarise(_ result: ABMAPIService.FleetResult) -> Summary {
        let now = Date()
        var outOfWarranty = 0
        var noRecord = 0
        var unavailable = 0
        var inferred = 0
        var missing = 0

        for record in result.records {
            switch record.warrantyState {
            case .expired:
                outOfWarranty += 1
            case .noRecord:
                noRecord += 1
            case .active(let end):
                // An "active" record whose end date has already passed is treated as expired: the
                // date is what an administrator will act on, not Apple's status field.
                if let end, end < now { outOfWarranty += 1 }
            case .unavailable:
                unavailable += 1
            }

            if record.purchaseDate == nil {
                missing += 1
            } else if !record.purchaseDateSource.isReliable {
                inferred += 1
            }
        }

        return Summary(
            macCount: result.records.count,
            outOfWarranty: outOfWarranty,
            noWarrantyRecord: noRecord,
            warrantyUnavailable: unavailable,
            inferredPurchaseDates: inferred,
            missingPurchaseDates: missing,
            nonMacCount: result.nonMacCount,
            failedCount: result.failures.count,
            failureReason: result.commonestFailureReason
        )
    }
}
