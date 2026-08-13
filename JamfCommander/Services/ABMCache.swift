//
//  ABMCache.swift
//  JamfCommander
//
//  On-disk cache for Apple Business Manager fleet data.
//

import Foundation

/// Persists the Apple Business Manager fleet between launches.
///
/// A full refresh is two requests per device with no bulk warranty endpoint, so it cannot run when a
/// view appears. Purchase and warranty data changes only when a device is bought, disposed of, or an
/// AppleCare contract is taken out, which makes a week-long lifetime generous rather than risky.
///
/// The file holds **asset data** — serials, models, order numbers — and no credentials. Nothing in a
/// snapshot may ever be a secret; those belong in `KeychainStore`.
actor ABMCache {

    static let shared = ABMCache()

    /// Seven days. Entries older than this are refreshed in the background; an explicit refresh
    /// ignores it entirely.
    nonisolated static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    nonisolated struct Snapshot: Codable, Sendable {
        let records: [ABMDeviceRecord]
        let refreshedAt: Date
        /// The MDM server the snapshot was scoped to. A snapshot taken against a different server is
        /// discarded rather than shown, since it describes a different fleet.
        let mdmServerId: String

        func isStale(from reference: Date = Date()) -> Bool {
            reference.timeIntervalSince(refreshedAt) > ABMCache.timeToLive
        }
    }

    enum CacheError: LocalizedError {
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .locationUnavailable:
                return "The Apple Business Manager cache location could not be opened."
            }
        }
    }

    private var cached: Snapshot?

    // MARK: - Reading

    /// The stored snapshot for the given MDM server, or `nil` when there is none or it belongs to a
    /// different server.
    func snapshot(forServer mdmServerId: String) -> Snapshot? {
        let snapshot = cached ?? readFromDisk()
        cached = snapshot

        guard let snapshot, snapshot.mdmServerId == mdmServerId else { return nil }
        return snapshot
    }

    // MARK: - Writing

    func store(_ snapshot: Snapshot) throws {
        cached = snapshot

        let url = try fileURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    func clear() {
        cached = nil
        guard let url = try? fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Storage

    private func readFromDisk() -> Snapshot? {
        guard let url = try? fileURL(),
              let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // A snapshot written by an older build may no longer decode. Treating that as "no cache" is
        // correct: it costs one refresh, where crashing or reporting an error would cost more.
        return try? decoder.decode(Snapshot.self, from: data)
    }

    private func fileURL() throws -> URL {
        let manager = FileManager.default

        guard let support = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            throw CacheError.locationUnavailable
        }

        let directory = support.appendingPathComponent("JamfCommander", isDirectory: true)

        if !manager.fileExists(atPath: directory.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("abm-fleet.json", isDirectory: false)
    }
}
