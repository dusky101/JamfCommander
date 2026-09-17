//
//  BlueprintModels.swift
//  JamfCommander
//
//  Models for Jamf blueprints, served by the Platform API Gateway rather than the
//  Jamf Pro Classic/Pro APIs the rest of the app uses. Shapes below are taken from
//  the Platform API reference (developer.jamf.com/platform-api) — see
//  docs/JAMF_API_REFERENCE.md for the endpoint list.
//

import Foundation

// MARK: - Region

/// The three regions the Platform API Gateway is deployed in. Tokens are region-locked:
/// a token issued by one region's host is rejected with 401 by another, so the region
/// chosen here governs both the token request and every subsequent call.
nonisolated enum PlatformRegion: String, CaseIterable, Identifiable, Sendable {
    case us
    case eu
    case apac

    var id: String { rawValue }

    /// Label for the region picker in Settings.
    var displayName: String {
        switch self {
        case .us: return "United States (us)"
        case .eu: return "Europe (eu)"
        case .apac: return "Asia Pacific (apac)"
        }
    }

    /// Base host for both the token endpoint and the platform APIs.
    var host: String { "https://\(rawValue).api.jamfcloud.com" }
}

// MARK: - Blueprints

/// A blueprint as returned by `GET /blueprints/v1/blueprints`.
///
/// The list endpoint returns only the summary fields below — scope and steps come back
/// from `GET /blueprints/v1/blueprints/{id}` and are shown in the inspector as raw JSON
/// rather than being modelled, so an unfamiliar component payload is never silently dropped.
nonisolated struct Blueprint: Identifiable, Decodable, Sendable, Hashable {
    let id: String
    let name: String
    let description: String?
    /// ISO 8601 timestamps, kept as strings so an unexpected fractional-seconds format
    /// degrades to "no date shown" rather than failing the whole decode.
    let created: String?
    let updated: String?
    let deploymentState: BlueprintDeploymentState?

    private enum CodingKeys: String, CodingKey {
        case id, identifier, blueprintId
        case name, description, created, updated, deploymentState
    }

    /// Decoded tolerantly on purpose.
    ///
    /// The synthesised decoder treats every non-optional property as mandatory and throws on any
    /// type it did not expect, so one unusual record makes the whole list unreadable and the
    /// failure gives no clue which record caused it. A blueprint with no usable identifier is
    /// genuinely unusable and is dropped by the envelope below; anything else is shown, with a
    /// placeholder name if the server sent none, so nothing is silently hidden.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? container.decode(String.self, forKey: .id) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: .identifier) {
            id = value
        } else if let value = try? container.decode(String.self, forKey: .blueprintId) {
            id = value
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "No blueprint identifier found."
            )
        }

        name = (try? container.decode(String.self, forKey: .name))?
            .nilIfEmpty ?? "Untitled blueprint"
        description = try? container.decode(String.self, forKey: .description)
        created = try? container.decode(String.self, forKey: .created)
        updated = try? container.decode(String.self, forKey: .updated)
        deploymentState = try? container.decode(
            BlueprintDeploymentState.self,
            forKey: .deploymentState
        )
    }

    /// Deployment state word reported by the server, e.g. "DEPLOYED". Only the server's own
    /// vocabulary is shown — the app does not map it onto an invented set of states.
    var deploymentStateText: String {
        deploymentState?.state?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Unknown"
    }

    var createdDate: Date? { BlueprintDateParser.date(from: created) }
    var updatedDate: Date? { BlueprintDateParser.date(from: updated) }
}

nonisolated struct BlueprintDeploymentState: Codable, Sendable, Hashable {
    let state: String?
    let lastDeployment: BlueprintLastDeployment?
}

nonisolated struct BlueprintLastDeployment: Codable, Sendable, Hashable {
    let started: String?
    let state: String?

    var startedDate: Date? { BlueprintDateParser.date(from: started) }
}

/// Envelope for `GET /blueprints/v1/blueprints`. Unlike the device-groups API this one
/// returns the short envelope — `results` and `totalCount` only.
nonisolated struct BlueprintListResponse: Decodable, Sendable {
    let results: [Blueprint]
    let totalCount: Int?

    /// Number of records the server sent that could not be read at all. Surfaced rather than
    /// swallowed, so a partial list is never mistaken for a complete one.
    let unreadableCount: Int

    private enum CodingKeys: String, CodingKey {
        case results, blueprints, totalCount
    }

    /// Wrapper that turns a single unreadable record into `nil` instead of failing the array.
    private struct Failable: Decodable {
        let value: Blueprint?

        init(from decoder: Decoder) throws {
            value = try? Blueprint(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        func unpack(_ raw: [Failable]) -> ([Blueprint], Int) {
            let decoded = raw.compactMap(\.value)
            return (decoded, raw.count - decoded.count)
        }

        // Some Jamf endpoints return a bare array rather than an envelope.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode([Failable].self) {
            (results, unreadableCount) = unpack(raw)
            totalCount = results.count
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode([Failable].self, forKey: .results))
            ?? (try? container.decode([Failable].self, forKey: .blueprints))
            ?? []
        (results, unreadableCount) = unpack(raw)
        // `try?` rather than the synthesised decodeIfPresent, which throws on an unexpected type
        // and would fail the whole response over a count.
        totalCount = try? container.decode(Int.self, forKey: .totalCount)
    }
}

// MARK: - Device groups

/// A device group from `GET /device-groups/v1/device-groups`.
///
/// These are platform device groups identified by UUID, and they are what
/// `scope.deviceGroups` on a blueprint refers to. They are **not** the numeric Jamf Pro
/// computer groups returned by `JamfAPIService.fetchComputerGroups()`; the two are not
/// interchangeable.
nonisolated struct PlatformDeviceGroup: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let description: String?
    /// "COMPUTER" or "MOBILE".
    let deviceType: String?
    /// "SMART" or "STATIC".
    let groupType: String?
    let memberCount: Int?

    /// SF Symbol for the group's device type, falling back to a neutral symbol for any
    /// value the API adds later.
    var deviceTypeIcon: String {
        switch deviceType?.uppercased() {
        case "COMPUTER": return "desktopcomputer"
        case "MOBILE": return "iphone"
        default: return "questionmark.square.dashed"
        }
    }

    /// Short human-readable summary used in the group picker, e.g. "Smart · Computer · 42 devices".
    var summary: String {
        var parts: [String] = []
        if let groupType, !groupType.isEmpty {
            parts.append(groupType.capitalized)
        }
        if let deviceType, !deviceType.isEmpty {
            parts.append(deviceType.capitalized)
        }
        if let memberCount {
            parts.append(memberCount == 1 ? "1 device" : "\(memberCount) devices")
        }
        return parts.joined(separator: " · ")
    }
}

/// Envelope for `GET /device-groups/v1/device-groups` — the full paginated form.
nonisolated struct PlatformDeviceGroupPage: Codable, Sendable {
    let results: [PlatformDeviceGroup]
    let page: Int?
    let pageSize: Int?
    let totalCount: Int?
    let totalPages: Int?
    let hasNext: Bool?
    let hasPrevious: Bool?
}

// MARK: - Date parsing

/// Lenient ISO 8601 parsing for the `created`/`updated`/`started` timestamps.
///
/// Jamf returns `2025-04-01T12:00:00Z` in the documented example, but fractional seconds
/// appear elsewhere in the platform, so both forms are tried before giving up.
nonisolated enum BlueprintDateParser {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withFractional.date(from: string) ?? plain.date(from: string)
    }

    /// Medium date, short time — matches the formatting used elsewhere in the app.
    static func display(_ string: String?) -> String {
        guard let date = date(from: string) else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Helpers

nonisolated extension String {
    /// Nil for an empty string, so `??` can fall through to a placeholder.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Components

/// One component from `GET blueprints/v1/blueprint-components`.
///
/// Decoded defensively. The published reference does not show this endpoint's response body, and
/// the component catalogue is tenant- and version-dependent — Jamf ships new components (for
/// example a native Extensible SSO component for macOS 27) ahead of the API reference listing them.
/// So the identifier is accepted under `identifier` or `id`, and the label under `name`,
/// `displayName` or `title`, rather than assuming one spelling. The raw JSON is always available
/// alongside this, so nothing is hidden if the decode misses a field.
nonisolated struct BlueprintComponent: Identifiable, Decodable, Sendable, Hashable {
    let identifier: String
    let name: String?
    let description: String?

    var id: String { identifier }

    /// Label for the list, falling back to the identifier when no friendly name comes back.
    var displayTitle: String {
        name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? identifier
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, id, name, displayName, title, description, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? container.decode(String.self, forKey: .identifier) {
            identifier = value
        } else if let value = try? container.decode(String.self, forKey: .id) {
            identifier = value
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier,
                in: container,
                debugDescription: "No component identifier found under 'identifier' or 'id'."
            )
        }

        name = (try? container.decode(String.self, forKey: .name))
            ?? (try? container.decode(String.self, forKey: .displayName))
            ?? (try? container.decode(String.self, forKey: .title))

        description = (try? container.decode(String.self, forKey: .description))
            ?? (try? container.decode(String.self, forKey: .summary))
    }
}

/// Envelope for the component list. Tolerates a bare array as well as `results` or `components`,
/// since the reference does not publish this response's shape.
nonisolated struct BlueprintComponentListResponse: Decodable, Sendable {
    let results: [BlueprintComponent]
    let totalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case results, components, totalCount
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let array = try? single.decode([BlueprintComponent].self) {
            results = array
            totalCount = array.count
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? container.decode([BlueprintComponent].self, forKey: .results))
            ?? (try? container.decode([BlueprintComponent].self, forKey: .components))
            ?? []
        totalCount = try? container.decode(Int.self, forKey: .totalCount)
    }
}
