//
//  ABMAPIService.swift
//  JamfCommander
//
//  Read-only client for the Apple Business Manager API.
//

import Foundation
import Combine

/// Talks to Apple Business Manager for purchase and warranty data.
///
/// **Every request this service makes is a GET.** The ABM API has no granular permissions — the key
/// it signs with can also reassign and release devices — so the read-only discipline lives here, in
/// the only place that builds ABM requests. Do not add a write path.
///
/// Shared rather than owned by `ContentView`, because the configuration sheet needs it to test the
/// connection and `ContentView` does not pass a service into that sheet.
final class ABMAPIService: ObservableObject {

    static let shared = ABMAPIService()

    // MARK: - Endpoints

    /// The token is POSTed here. Note this URL has **no** `/v2/` — the `aud` claim does. See
    /// `ABMClientAssertion.audience`.
    private static let tokenURLString = "https://account.apple.com/auth/oauth2/token"
    private static let apiBase = "https://api-business.apple.com/v1"

    /// Apple accepts up to 1000; 999 is the value proven against the live tenant.
    static let pageLimit = 999

    // MARK: - Throttling

    private static let maxRetries = 4
    /// Rate limits get a longer budget than server errors: when a bulk fetch trips an unpublished
    /// limit, waiting is the only thing that helps and giving up early loses the device entirely.
    private static let maxRateLimitRetries = 8
    /// Refresh this far ahead of expiry so a request never starts with a token about to lapse.
    private static let refreshMargin: TimeInterval = 300

    // MARK: - Errors

    enum ABMError: LocalizedError {
        case notConfigured
        case invalidURL
        case authFailed(String?)
        case requestFailed(String?)
        case httpError(Int, String?)
        case rateLimited
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Apple Business Manager is not configured. Add the Client ID, Key ID and private key in Settings."
            case .invalidURL:
                return "The Apple Business Manager address could not be built."
            case .authFailed(let detail):
                let base = "Apple Business Manager rejected the credentials."
                guard let detail, !detail.isEmpty else {
                    return "\(base) Check the Client ID and Key ID match the private key you imported."
                }
                return "\(base) \(detail)"
            case .requestFailed(let detail):
                guard let detail, !detail.isEmpty else {
                    return "Could not reach Apple Business Manager."
                }
                return "Could not reach Apple Business Manager: \(detail)"
            case .httpError(let code, let detail):
                guard let detail, !detail.isEmpty else {
                    return "Apple Business Manager returned an error (HTTP \(code))."
                }
                return "Apple Business Manager returned an error (HTTP \(code)): \(detail)"
            case .rateLimited:
                return "Apple Business Manager is rate limiting requests. Try again shortly."
            case .decodingFailed:
                return "The response from Apple Business Manager could not be read."
            }
        }
    }

    // MARK: - Token cache

    private struct CachedToken {
        let value: String
        let expiresAt: Date

        var isUsable: Bool {
            expiresAt.timeIntervalSinceNow > ABMAPIService.refreshMargin
        }
    }

    /// In memory only. The token is a bearer credential and is never persisted.
    private var cachedToken: CachedToken?
    /// Coalesces concurrent token requests, so a bulk fetch does not open one exchange per task.
    private var tokenRequest: Task<CachedToken, Error>?

    private init() {}

    // MARK: - Configuration

    var isConfigured: Bool {
        CredentialStore.shared.hasABMCredentials
    }

    /// Drops the cached token. Called when the credentials change so the next request re-signs.
    func invalidateSession() {
        cachedToken = nil
        tokenRequest?.cancel()
        tokenRequest = nil
    }

    // MARK: - Public API

    /// Every MDM server registered in the organisation.
    func fetchMDMServers() async throws -> [ABMMDMServer] {
        try await fetchAllPages(path: "mdmServers", as: ABMMDMServer.self)
    }

    /// The serial numbers assigned to one MDM server.
    ///
    /// This endpoint returns **identifiers only** — no model, no order number, no warranty. Device
    /// attributes have to come from `/orgDevices`. Note the path is `relationships/devices`:
    /// `/mdmServers/{id}/devices` returns 403, because the relationship allows `GET_RELATIONSHIP`
    /// rather than `GET_RELATED`.
    func fetchAssignedSerials(mdmServerId: String) async throws -> [String] {
        let identifiers = try await fetchAllPages(
            path: "mdmServers/\(mdmServerId)/relationships/devices",
            as: ABMDeviceIdentifier.self
        )
        return identifiers.map(\.id)
    }

    /// Proves the whole chain — assertion, token exchange, and an authorised call — and reports
    /// something human-readable rather than a bare success.
    func testConnection(mdmServerId: String?) async throws -> ABMConnectionReport {
        invalidateSession()

        let servers = try await fetchMDMServers()

        guard let mdmServerId, !mdmServerId.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ABMConnectionReport(servers: servers, assignedDeviceCount: nil, selectedServerName: nil)
        }

        let serials = try await fetchAssignedSerials(mdmServerId: mdmServerId)
        let name = servers.first { $0.id == mdmServerId }?.displayName

        return ABMConnectionReport(
            servers: servers,
            assignedDeviceCount: serials.count,
            selectedServerName: name
        )
    }

    // MARK: - Paging

    /// Follows cursor paging to exhaustion. The **absence** of `nextCursor` ends the walk; the
    /// returned count is not a reliable terminator.
    ///
    /// Internal rather than private so `+Fleet` can reach it, matching how `JamfAPIService` exposes
    /// its shared helpers to its extensions.
    func fetchAllPages<Element: Codable & Sendable>(
        path: String,
        as type: Element.Type
    ) async throws -> [Element] {
        var results: [Element] = []
        var cursor: String?

        repeat {
            var query = [URLQueryItem(name: "limit", value: String(Self.pageLimit))]
            if let cursor {
                query.append(URLQueryItem(name: "cursor", value: cursor))
            }

            let data = try await authorisedData(path: path, query: query)

            do {
                let page = try JSONDecoder().decode(ABMListResponse<Element>.self, from: data)
                results.append(contentsOf: page.data)
                cursor = page.nextCursor
            } catch {
                throw ABMError.decodingFailed
            }
        } while cursor != nil

        return results
    }

    // MARK: - Requests

    /// An authorised GET, retrying rate limits and transient server errors, and refreshing the token
    /// once on a 401 as Apple's documentation directs.
    ///
    /// Internal so `+Fleet` can use it. Every caller must keep this a GET — see the type's note.
    func authorisedData(path: String, query: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(string: "\(Self.apiBase)/\(path)") else {
            throw ABMError.invalidURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ABMError.invalidURL }

        var hasRefreshed = false
        var attempt = 0
        var rateLimitAttempt = 0
        var transportAttempt = 0

        while true {
            let token = try await accessToken()

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            // Workaround for a server-side fault: `api-business.apple.com` has been observed returning
            // `transfer-encoding: chunked` on an HTTP/2 connection, which RFC 9113 forbids. CFNetwork
            // rejects the frame and drops the connection, surfacing as URLError -1005. Asking for an
            // unencoded body encourages the server to send a buffered response with a Content-Length
            // instead of a chunked one. The payloads are small, so losing compression costs nothing.
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.timeoutInterval = 30

            var payload: (data: Data, response: URLResponse)?
            do {
                payload = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code != .cancelled {
                // Transport failures across a bulk run are often transient — a timeout, or a
                // connection the server closed between requests — so one is not fatal to the device.
                guard transportAttempt < Self.maxRetries else {
                    ABMLog.error("GET \(path) failed after \(transportAttempt + 1) attempts: \(Self.describe(error))")
                    throw ABMError.requestFailed(Self.describe(error))
                }
                ABMLog.warning("GET \(path) — \(Self.describe(error)); retry \(transportAttempt + 1) of \(Self.maxRetries)")
                try await sleep(seconds: backoff(for: transportAttempt))
                transportAttempt += 1
                continue
            } catch {
                ABMLog.error("GET \(path) failed: \(error.localizedDescription)")
                throw ABMError.requestFailed(error.localizedDescription)
            }

            guard let payload else { throw ABMError.requestFailed(nil) }
            let data = payload.data

            guard let http = payload.response as? HTTPURLResponse else {
                throw ABMError.requestFailed("The response was not an HTTP response.")
            }

            switch http.statusCode {
            case 200...299:
                return data

            case 401 where !hasRefreshed:
                ABMLog.warning("GET \(path) returned 401; refreshing the token and retrying")
                hasRefreshed = true
                invalidateSession()

            case 429:
                guard rateLimitAttempt < Self.maxRateLimitRetries else {
                    ABMLog.error("GET \(path) rate limited after \(rateLimitAttempt) waits; giving up")
                    throw ABMError.rateLimited
                }
                let wait = retryAfter(from: http) ?? backoff(for: rateLimitAttempt)
                ABMLog.warning("GET \(path) returned 429; waiting \(String(format: "%.1f", wait))s")
                try await sleep(seconds: wait)
                rateLimitAttempt += 1

            case 500...599:
                guard attempt < Self.maxRetries else {
                    ABMLog.error("GET \(path) returned \(http.statusCode) after \(attempt) retries")
                    throw ABMError.httpError(http.statusCode, decodeErrorSummary(from: data))
                }
                ABMLog.warning("GET \(path) returned \(http.statusCode); retry \(attempt + 1) of \(Self.maxRetries)")
                try await sleep(seconds: backoff(for: attempt))
                attempt += 1

            default:
                ABMLog.error("GET \(path) returned \(http.statusCode)")
                throw ABMError.httpError(http.statusCode, decodeErrorSummary(from: data))
            }
        }
    }

    // MARK: - Token

    private func accessToken() async throws -> String {
        if let cachedToken, cachedToken.isUsable {
            return cachedToken.value
        }

        if let tokenRequest {
            return try await tokenRequest.value.value
        }

        let request = Task { try await self.requestToken() }
        tokenRequest = request
        defer { tokenRequest = nil }

        let token = try await request.value
        cachedToken = token
        return token.value
    }

    /// Signs a fresh 15-minute assertion and exchanges it for an access token.
    private func requestToken() async throws -> CachedToken {
        let store = CredentialStore.shared
        let clientId = store.abmClientId
        let keyId = store.abmKeyId

        guard !clientId.isEmpty, !keyId.isEmpty, let pem = store.abmPrivateKeyPEM(), !pem.isEmpty else {
            throw ABMError.notConfigured
        }

        let assertion = try ABMClientAssertion.make(
            clientId: clientId,
            keyId: keyId,
            privateKeyPEM: pem
        )

        guard let url = URL(string: Self.tokenURLString) else { throw ABMError.invalidURL }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_assertion_type", value: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"),
            URLQueryItem(name: "client_assertion", value: assertion),
            URLQueryItem(name: "scope", value: "business.api")
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.timeoutInterval = 30

        // The token is fetched once an hour, but a transport blip here fails the entire run rather
        // than one device, so it gets the same retry treatment.
        var payload: (data: Data, response: URLResponse)?
        var transportAttempt = 0

        while payload == nil {
            do {
                payload = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code != .cancelled {
                guard transportAttempt < Self.maxRetries else {
                    throw ABMError.requestFailed(Self.describe(error))
                }
                try await sleep(seconds: backoff(for: transportAttempt))
                transportAttempt += 1
            } catch {
                throw ABMError.requestFailed(error.localizedDescription)
            }
        }

        guard let payload else { throw ABMError.requestFailed(nil) }
        let data = payload.data

        guard let http = payload.response as? HTTPURLResponse else {
            throw ABMError.requestFailed("The response was not an HTTP response.")
        }

        guard http.statusCode == 200 else {
            ABMLog.error("Token exchange failed with HTTP \(http.statusCode)")
            throw ABMError.authFailed(decodeTokenErrorSummary(from: data))
        }

        guard let token = try? JSONDecoder().decode(ABMTokenResponse.self, from: data) else {
            ABMLog.error("Token response could not be decoded")
            throw ABMError.decodingFailed
        }

        ABMLog.info("Access token obtained, valid for \(token.expiresIn ?? 3600)s")

        // Apple issues one-hour tokens; the response is trusted over that assumption.
        let lifetime = TimeInterval(token.expiresIn ?? 3600)
        return CachedToken(value: token.accessToken, expiresAt: Date().addingTimeInterval(lifetime))
    }

    // MARK: - Helpers

    /// A readable description of a transport failure, carrying the numeric code so an intermittent
    /// fault can actually be identified rather than guessed at.
    private static func describe(_ error: URLError) -> String {
        let reason: String
        switch error.code {
        case .timedOut:
            reason = "the request timed out"
        case .networkConnectionLost:
            reason = "the connection was closed"
        case .cannotConnectToHost:
            reason = "the host refused the connection"
        case .notConnectedToInternet:
            reason = "there is no internet connection"
        case .cannotFindHost, .dnsLookupFailed:
            reason = "the host could not be found"
        case .secureConnectionFailed:
            reason = "the secure connection failed"
        default:
            reason = error.localizedDescription
        }
        return "\(reason) (URLError \(error.errorCode))"
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(header) else { return nil }
        return max(1, min(seconds, 60))
    }

    /// Exponential backoff with jitter. Without the jitter, concurrent requests that trip the same
    /// limit sleep for the same interval, wake together and trip it again.
    private func backoff(for attempt: Int) -> TimeInterval {
        // Capped at 10s rather than 30s: a bulk run waits on this once per device, and a 30s ceiling
        // turned a throttled fetch into something that looked hung.
        let base = min(pow(2.0, Double(attempt)), 10)
        return base + Double.random(in: 0...min(base, 2))
    }

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Apple's API error messages describe the request rather than the account, so there is nothing
    /// sensitive to strip before showing them.
    private func decodeErrorSummary(from data: Data) -> String? {
        try? JSONDecoder().decode(ABMErrorResponse.self, from: data).summary
    }

    /// The token endpoint collapses every signing mistake to `invalid_client`, so the raw code is
    /// translated into the two things that actually cause it.
    private func decodeTokenErrorSummary(from data: Data) -> String? {
        guard let failure = try? JSONDecoder().decode(ABMTokenErrorResponse.self, from: data),
              let code = failure.error else { return nil }

        if let description = failure.errorDescription, !description.isEmpty {
            return description
        }

        if code == "invalid_client" {
            return "Apple reported 'invalid_client', which means either the Client ID and Key ID do not match the imported private key, or the key is not the one this ABM API account was issued with."
        }

        return code
    }
}
