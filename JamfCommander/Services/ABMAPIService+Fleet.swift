//
//  ABMAPIService+Fleet.swift
//  JamfCommander
//
//  Fetching device attributes and warranty for the Macs assigned to an MDM server.
//

import Foundation

extension ABMAPIService {

    /// The pause between warranty requests.
    ///
    /// Apple publishes no rate limit for this API. The one measured figure comes from the
    /// proof-of-concept extract: 153 sequential requests 150ms apart were never throttled. Fetching
    /// three devices at a time — six requests, roughly seven per second — was throttled after about a
    /// minute, and the resulting backoff turned the run into a crawl. This matches the proven pace.
    private static var requestDelay: TimeInterval { 0.15 }

    // MARK: - Single device

    /// Attributes for one device. Returns `nil` when ABM has no record for the serial.
    ///
    /// Not used by `fetchFleet`, which takes attributes from the collection endpoint in one call.
    /// Kept for looking up a single machine without a full refresh.
    ///
    /// The verified payloads for this API all come from collection endpoints, which wrap results in
    /// `data`. A single-resource response conventionally does the same, but that is convention rather
    /// than something proven against the tenant — so an unwrapped object is accepted too, following
    /// the fallback-decoding pattern the Jamf models already use for cross-endpoint shapes.
    func fetchDeviceAttributes(serial: String) async throws -> ABMDeviceAttributes? {
        let data = try await authorisedData(path: "orgDevices/\(serial)", query: [])
        let decoder = JSONDecoder()

        if let wrapped = try? decoder.decode(ABMSingleResponse<ABMDeviceEnvelope>.self, from: data) {
            return wrapped.data.attributes
        }

        if let bare = try? decoder.decode(ABMDeviceEnvelope.self, from: data) {
            return bare.attributes
        }

        throw ABMError.decodingFailed
    }

    /// Every coverage record for one device.
    ///
    /// There is no bulk warranty endpoint — this is one request per device, which is both why the
    /// results are cached and why the pacing above matters.
    func fetchCoverage(serial: String) async throws -> [ABMCoverage] {
        let data = try await authorisedData(path: "orgDevices/\(serial)/appleCareCoverage", query: [])

        guard let response = try? JSONDecoder().decode(
            ABMListResponse<ABMCoverageEnvelope>.self,
            from: data
        ) else {
            throw ABMError.decodingFailed
        }

        return response.data.compactMap(\.attributes)
    }

    // MARK: - Results

    /// One device that could not be retrieved, and why.
    ///
    /// The reason is carried rather than discarded: a run that quietly returns 34 of 153 devices is
    /// indistinguishable from a rate limit, an auth lapse and a decoding fault unless the failure
    /// says which it was.
    nonisolated struct FleetFailure: Sendable, Hashable {
        let serialNumber: String
        let reason: String
    }

    /// What a fleet fetch found, including the devices it could not retrieve.
    nonisolated struct FleetResult: Sendable {
        let records: [ABMDeviceRecord]
        /// Serials assigned to the MDM server in ABM.
        let assignedSerialCount: Int
        /// Assigned serials whose device record was not a Mac.
        let nonMacCount: Int
        /// Devices that could not be retrieved at all. Reported rather than silently dropped.
        let failures: [FleetFailure]

        /// The most frequent failure reason, for the summary line. When a bulk fetch degrades it is
        /// almost always for one reason, and naming it is what makes the run actionable.
        var commonestFailureReason: String? {
            let counts = Dictionary(grouping: failures, by: \.reason).mapValues(\.count)
            return counts.max { $0.value < $1.value }?.key
        }
    }

    // MARK: - Fleet

    /// Fetches every Mac assigned to the given MDM server, with its warranty.
    ///
    /// Three stages:
    /// 1. The MDM server's membership list — identifiers only, and **the scope for everything below**.
    /// 2. One paged pass over `/orgDevices` for attributes, filtered immediately to that membership.
    /// 3. One warranty request per in-scope Mac, paced.
    ///
    /// Stage 2 returns every device in the organisation, including those managed elsewhere. They are
    /// discarded at the filter — never decoded into a record, never cached, never shown or exported.
    /// The alternative, fetching each device individually, doubles the request count to 306 and is
    /// what Apple throttled.
    ///
    /// A device that fails is recorded in `failures` and omitted; one bad serial never aborts the run.
    /// A device whose *warranty* call fails is kept with `coverage == nil`, so the UI reports
    /// "unavailable" rather than claiming it is out of warranty.
    ///
    /// - Parameter onProgress: called with (completed, total) as warranty is fetched.
    func fetchFleet(
        mdmServerId: String,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> FleetResult {

        ABMLog.info("Refresh started for MDM server \(mdmServerId)")

        // 1. Scope.
        let assignedSerials = Set(try await fetchAssignedSerials(mdmServerId: mdmServerId))
        ABMLog.info("Stage 1: \(assignedSerials.count) serials assigned to the MDM server")

        guard !assignedSerials.isEmpty else {
            ABMLog.warning("No devices are assigned to that MDM server; nothing to fetch")
            return FleetResult(records: [], assignedSerialCount: 0, nonMacCount: 0, failures: [])
        }

        // 2. Attributes for the whole organisation in one paged call, filtered to the scope as we go.
        let allDevices = try await fetchAllPages(path: "orgDevices", as: ABMDeviceEnvelope.self)
        ABMLog.info("Stage 2: \(allDevices.count) device records in the organisation")

        var scoped: [(serial: String, attributes: ABMDeviceAttributes)] = []
        var nonMacCount = 0

        for envelope in allDevices {
            let serial = envelope.attributes?.serialNumber ?? envelope.id
            guard assignedSerials.contains(serial) else { continue }
            guard let attributes = envelope.attributes else { continue }
            guard attributes.isMac else {
                nonMacCount += 1
                continue
            }
            scoped.append((serial, attributes))
        }

        var failures: [FleetFailure] = []

        // Assigned to the MDM server but absent from /orgDevices. Worth reporting rather than
        // quietly returning a smaller fleet than the server says it has.
        let matched = Set(scoped.map(\.serial))
        for missing in assignedSerials.subtracting(matched).sorted() {
            ABMLog.warning("\(missing) is assigned to the MDM server but has no /orgDevices record")
            failures.append(
                FleetFailure(
                    serialNumber: missing,
                    reason: "Assigned to the MDM server but no device record exists in Apple Business Manager."
                )
            )
        }

        ABMLog.info("Stage 2 filtered to \(scoped.count) Macs in scope (\(nonMacCount) not a Mac, \(failures.count) with no record)")
        ABMLog.info("Stage 3: fetching warranty for \(scoped.count) devices at \(Int(Self.requestDelay * 1000))ms intervals")

        // 3. Warranty, one request per in-scope Mac.
        let fetchedAt = Date()
        var records: [ABMDeviceRecord] = []
        records.reserveCapacity(scoped.count)

        onProgress?(0, scoped.count)

        var coverageFailures = 0

        for (index, entry) in scoped.enumerated() {
            let position = "\(index + 1)/\(scoped.count)"

            // `nil` and `[]` mean different things downstream, so a failed call must not become an
            // empty array. An empty array is a real answer: the device has no coverage records.
            var coverage: [ABMCoverage]?
            do {
                coverage = try await fetchCoverage(serial: entry.serial)
                ABMLog.info("\(position) \(entry.serial) — \(coverage?.count ?? 0) coverage record(s)")
            } catch {
                coverageFailures += 1
                ABMLog.warning("\(position) \(entry.serial) — warranty unavailable: \(error.localizedDescription)")
            }

            records.append(
                ABMDeviceRecord(
                    serialNumber: entry.serial,
                    attributes: entry.attributes,
                    coverage: coverage,
                    fetchedAt: fetchedAt
                )
            )

            onProgress?(index + 1, scoped.count)

            if index + 1 < scoped.count {
                try await sleep(seconds: Self.requestDelay)
            }
        }

        ABMLog.info("Refresh finished: \(records.count) Macs, \(coverageFailures) without warranty data, \(failures.count) not retrieved")

        return FleetResult(
            records: records.sorted { $0.serialNumber < $1.serialNumber },
            assignedSerialCount: assignedSerials.count,
            nonMacCount: nonMacCount,
            failures: failures.sorted { $0.serialNumber < $1.serialNumber }
        )
    }
}
