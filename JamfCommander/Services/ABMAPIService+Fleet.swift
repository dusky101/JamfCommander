//
//  ABMAPIService+Fleet.swift
//  JamfCommander
//
//  Fetching device attributes and warranty for the Macs assigned to an MDM server.
//

import Foundation

extension ABMAPIService {

    /// Devices fetched per batch, and the pause between batches.
    ///
    /// **Deliberately lower than the Jamf throttle.** Apple publishes no rate limit for this API. The
    /// only measured figure is from the proof-of-concept extract: 153 sequential calls at 150ms apart
    /// were never throttled. Ten devices in flight — twenty requests, since each device needs two —
    /// was far past that and produced partial results that varied run to run.
    ///
    /// Three devices per batch with a half-second pause is roughly six requests per second, which
    /// stays near the proven rate while finishing in about a minute rather than three.
    private static var batchSize: Int { 3 }
    private static var batchDelay: TimeInterval { 0.5 }

    // MARK: - Single device

    /// Attributes for one device. Returns `nil` when ABM has no record for the serial.
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
    /// There is no bulk warranty endpoint — this is one request per device, which is the whole reason
    /// the results are cached rather than fetched on demand.
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

    // MARK: - Fleet

    /// One device that could not be retrieved, and why.
    ///
    /// The reason is carried rather than discarded: a run that quietly returns 18 of 153 devices is
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
        /// Assigned serials whose device record was not a Mac — iPhones or iPads on a mixed server.
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

    /// Fetches every Mac assigned to the given MDM server, with its warranty.
    ///
    /// Scoped from the MDM server's membership list rather than the bulk `/orgDevices` collection, so
    /// the iPhones and iPads in the organisation are never downloaded. That costs two requests per
    /// device instead of one shared list call, which the batching absorbs.
    ///
    /// A device that fails is recorded in `failedSerials` and omitted; one bad serial never aborts the
    /// run. A device whose *coverage* call fails is kept with `coverage == nil`, so the UI reports
    /// "unavailable" rather than claiming it is out of warranty.
    ///
    /// - Parameter onProgress: called with (completed, total) after each batch, on the main actor.
    func fetchFleet(
        mdmServerId: String,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> FleetResult {
        let serials = try await fetchAssignedSerials(mdmServerId: mdmServerId)

        guard !serials.isEmpty else {
            return FleetResult(records: [], assignedSerialCount: 0, nonMacCount: 0, failures: [])
        }

        let fetchedAt = Date()
        var records: [ABMDeviceRecord] = []
        var failures: [FleetFailure] = []
        var nonMacCount = 0
        var completed = 0

        records.reserveCapacity(serials.count)
        onProgress?(0, serials.count)

        for start in stride(from: 0, to: serials.count, by: Self.batchSize) {
            let batch = Array(serials[start..<min(start + Self.batchSize, serials.count)])

            let outcomes = await withTaskGroup(of: DeviceOutcome.self) { group in
                for serial in batch {
                    group.addTask {
                        await self.fetchRecord(serial: serial, fetchedAt: fetchedAt)
                    }
                }

                var collected: [DeviceOutcome] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            for outcome in outcomes {
                switch outcome {
                case .record(let record): records.append(record)
                case .notAMac: nonMacCount += 1
                case .failed(let failure): failures.append(failure)
                }
            }

            completed += batch.count
            onProgress?(completed, serials.count)

            if start + Self.batchSize < serials.count {
                try await sleep(seconds: Self.batchDelay)
            }
        }

        return FleetResult(
            records: records.sorted { $0.serialNumber < $1.serialNumber },
            assignedSerialCount: serials.count,
            nonMacCount: nonMacCount,
            failures: failures.sorted { $0.serialNumber < $1.serialNumber }
        )
    }

    /// The three ways one device can turn out.
    private enum DeviceOutcome: Sendable {
        case record(ABMDeviceRecord)
        case notAMac
        case failed(FleetFailure)
    }

    private func fetchRecord(serial: String, fetchedAt: Date) async -> DeviceOutcome {
        let attributes: ABMDeviceAttributes?
        do {
            attributes = try await fetchDeviceAttributes(serial: serial)
        } catch {
            return .failed(FleetFailure(serialNumber: serial, reason: error.localizedDescription))
        }

        guard let attributes else {
            return .failed(FleetFailure(serialNumber: serial, reason: "No device record in Apple Business Manager."))
        }

        // The Jamf Pro server should only hold Macs, but a mixed MDM server would otherwise put an
        // iPhone into the Computers views.
        guard attributes.isMac else { return .notAMac }

        // `nil` and `[]` mean different things downstream, so a failed call must not become an empty
        // array. An empty array is a real answer: the device has no coverage records.
        let coverage = try? await fetchCoverage(serial: serial)

        return .record(
            ABMDeviceRecord(
                serialNumber: serial,
                attributes: attributes,
                coverage: coverage,
                fetchedAt: fetchedAt
            )
        )
    }
}
