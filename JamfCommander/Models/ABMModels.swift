//
//  ABMModels.swift
//  JamfCommander
//
//  Apple Business Manager API payloads.
//

import Foundation

// MARK: - Token exchange

/// The response from `POST https://account.apple.com/auth/oauth2/token`.
nonisolated struct ABMTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String?
    /// Seconds. One hour in practice, but taken from the response rather than assumed.
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

/// The OAuth failure shape. `invalid_client` is what every signing mistake collapses to, so the
/// description is deliberately more helpful than the code itself.
nonisolated struct ABMTokenErrorResponse: Codable, Sendable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - Generic list envelope

/// Apple Business Manager wraps collections in `data`, with cursor paging under `meta.paging`.
///
/// **The absence of `nextCursor` is the terminator.** Comparing the returned count against the
/// requested limit is not reliable.
nonisolated struct ABMListResponse<Element: Codable & Sendable>: Codable, Sendable {
    let data: [Element]
    let meta: Meta?

    var nextCursor: String? { meta?.paging?.nextCursor }

    nonisolated struct Meta: Codable, Sendable {
        let paging: Paging?

        nonisolated struct Paging: Codable, Sendable {
            let nextCursor: String?
            let limit: Int?
        }
    }
}

/// The single-object equivalent of `ABMListResponse`, used by `/orgDevices/{serial}`.
nonisolated struct ABMSingleResponse<Element: Codable & Sendable>: Codable, Sendable {
    let data: Element
}

/// The error shape returned by `api-business.apple.com`.
nonisolated struct ABMErrorResponse: Codable, Sendable {
    let errors: [Detail]?

    nonisolated struct Detail: Codable, Sendable {
        let status: String?
        let code: String?
        let title: String?
        let detail: String?
    }

    /// A single readable line for the UI. Apple's messages describe the request, not the account, so
    /// there is nothing sensitive to strip.
    var summary: String? {
        guard let first = errors?.first else { return nil }
        return first.detail ?? first.title ?? first.code
    }
}

// MARK: - MDM servers

/// An MDM server registered in Apple Business Manager. Used to confirm the connection and to scope
/// the device fetch to the Macs assigned to Jamf Pro.
nonisolated struct ABMMDMServer: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let attributes: Attributes?

    nonisolated struct Attributes: Codable, Hashable, Sendable {
        let serverName: String?
        let serverType: String?
        let status: String?
        let defaultProductFamilies: [String]?
        let createdDateTime: String?
        let updatedDateTime: String?
        let lastConnectedDateTime: String?
    }

    /// The server's name, falling back to its identifier so a row is never blank.
    var displayName: String {
        guard let name = attributes?.serverName, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return id
        }
        return name
    }

    var isActive: Bool {
        attributes?.status?.uppercased() == "ACTIVE"
    }
}

/// One entry in `/mdmServers/{id}/relationships/devices`. Identifiers only — this endpoint carries no
/// attributes at all, so device detail has to come from `/orgDevices`.
nonisolated struct ABMDeviceIdentifier: Codable, Hashable, Sendable {
    let id: String
    let type: String?
}

// MARK: - Connection test

/// What a successful "Test connection" found, for display in the configuration sheet.
nonisolated struct ABMConnectionReport: Sendable {
    let servers: [ABMMDMServer]
    /// Devices assigned to the configured MDM server, when one is set.
    let assignedDeviceCount: Int?
    let selectedServerName: String?
}
