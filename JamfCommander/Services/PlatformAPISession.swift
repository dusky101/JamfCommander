//
//  PlatformAPISession.swift
//  JamfCommander
//
//  Token handling and request building for the Jamf Platform API Gateway.
//
//  This is deliberately separate from `JamfAPIService.authenticate(...)`. The two are
//  different services with different credentials:
//
//  - Jamf Pro API  — client created in Jamf Pro, token from
//                    `{instance}/api/v1/oauth/token`, no context header.
//  - Platform API  — integration created in **Jamf Account** scoped to a platform
//                    environment, token from `https://{region}.api.jamfcloud.com/auth/token`,
//                    every request carries `X-Environment-Id`.
//
//  A Jamf Pro API client cannot call the gateway, and gateway capability permissions
//  (`blueprints:read` and friends) are not Jamf Pro privileges.
//

import Foundation

// MARK: - Credentials

/// Where the Platform API settings live in `UserDefaults`.
///
/// These mirror the `@AppStorage` keys used by `ConfigurationView`, matching how the
/// Jamf Pro credentials are already stored. As with those, the secret is **not**
/// encrypted at rest — see `.claude/rules/auth-and-credentials.md`.
nonisolated enum PlatformCredentialsStore {
    static let regionKey = "platformRegion"
    static let environmentIdKey = "platformEnvironmentId"
    static let clientIdKey = "platformClientId"
    static let clientSecretKey = "platformClientSecret"

    /// Reads the current settings. Returns `nil` when any required value is missing, which
    /// the Blueprints module surfaces as a "not configured" state rather than a failed call.
    static func current(from defaults: UserDefaults = .standard) -> PlatformCredentials? {
        let region = PlatformRegion(rawValue: defaults.string(forKey: regionKey) ?? "") ?? .eu
        let environmentId = trimmed(defaults.string(forKey: environmentIdKey))
        let clientId = trimmed(defaults.string(forKey: clientIdKey))
        let clientSecret = trimmed(defaults.string(forKey: clientSecretKey))

        guard !environmentId.isEmpty, !clientId.isEmpty, !clientSecret.isEmpty else { return nil }

        return PlatformCredentials(
            region: region,
            environmentId: environmentId,
            clientId: clientId,
            clientSecret: clientSecret
        )
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One set of Platform API Gateway credentials.
///
/// Conforms to `Equatable` so the session can notice a settings change and drop a token that
/// was issued for the previous integration or region.
nonisolated struct PlatformCredentials: Sendable, Equatable {
    let region: PlatformRegion
    let environmentId: String
    let clientId: String
    let clientSecret: String
}

// MARK: - Errors

/// Failures from the Platform API Gateway, phrased so the message can be shown to an
/// administrator without exposing tokens, secrets or stack traces.
nonisolated enum PlatformAPIError: LocalizedError, Sendable {
    case notConfigured
    case invalidURL
    case authenticationFailed
    /// The gateway returns 403 for three separate conditions; the message spells them out
    /// because the status alone does not say which applies.
    case forbidden
    case notFound
    /// 400 — carries the server's validation detail, which for a blueprint is a description of
    /// the payload the administrator just supplied.
    case invalidRequest(String?)
    /// 409 — for a PATCH this means the blueprint is assigned to a division.
    case conflict(String?)
    case unsupportedMediaType
    case httpError(Int, String?)
    case decodingFailed(String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Platform API is not configured. Add the client ID, client secret, environment ID and region in Settings."
        case .invalidURL:
            return "The Platform API address could not be formed. Check the region in Settings."
        case .authenticationFailed:
            return "Could not obtain a Platform API token. Check the client ID and secret, and confirm the region matches the one the integration was created for."
        case .forbidden:
            return "The Platform API refused the request (403). The integration may be missing the required capability permission, may be scoped to a tenant rather than a platform environment, or the environment ID may be wrong."
        case .notFound:
            return "The blueprint no longer exists on the server."
        case .invalidRequest(let detail):
            if let detail, !detail.isEmpty {
                return "Jamf rejected the request as invalid: \(detail)"
            }
            return "Jamf rejected the request as invalid. Check the blueprint JSON against the Platform API reference."
        case .conflict(let detail):
            if let detail, !detail.isEmpty {
                return "Jamf reported a conflict: \(detail)"
            }
            return "Jamf reported a conflict. A blueprint assigned to a division cannot be updated through this API."
        case .unsupportedMediaType:
            return "Jamf rejected the content type of the request."
        case .httpError(let code, let detail):
            if let detail, !detail.isEmpty {
                return "The Platform API returned HTTP \(code): \(detail)"
            }
            return "The Platform API returned HTTP \(code)."
        case .decodingFailed(let detail):
            if let detail, !detail.isEmpty {
                return "The Platform API returned a response the app could not read — \(detail)."
            }
            return "The Platform API returned a response the app could not read."
        }
    }
}

// MARK: - Session

/// Owns the Platform API access token and builds authorised requests.
///
/// An actor because the token is shared mutable state: several dashboards can call the
/// gateway at once, and the token must be fetched once rather than per caller.
actor PlatformAPISession {

    /// Access tokens last 900 seconds. Refreshing this far ahead of expiry keeps a long
    /// paging loop from failing on a token that lapses mid-run.
    private static let refreshMargin: TimeInterval = 60

    /// Cap on how much of a server error body is surfaced. The body of a 400 is the
    /// validation detail an administrator needs, but it is never logged and never unbounded.
    private static let maxErrorDetailLength = 600

    private var credentials: PlatformCredentials?
    private var token: String?
    private var tokenExpiry: Date?
    /// In-flight token request, so concurrent callers share one round trip.
    private var refreshTask: Task<IssuedToken, Error>?

    /// Applies the current settings, discarding any cached token when they change.
    /// Called before each operation so a Settings edit takes effect without a restart.
    func configure(with newCredentials: PlatformCredentials?) {
        guard credentials != newCredentials else { return }
        credentials = newCredentials
        token = nil
        tokenExpiry = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// True when a complete set of credentials is present.
    var isConfigured: Bool { credentials != nil }

    /// Drops the cached token; the next call fetches a fresh one.
    func invalidateToken() {
        token = nil
        tokenExpiry = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Requests

    /// Sends an authorised request to the gateway and returns the body.
    ///
    /// - Parameters:
    ///   - method: HTTP method.
    ///   - path: Path beneath the region host, e.g. `blueprints/v1/blueprints`.
    ///   - query: Query items, unencoded.
    ///   - body: Request body, or `nil`.
    ///   - contentType: Content type for the body. PATCH on the blueprints API requires
    ///     `application/merge-patch+json`, which is why this is a parameter rather than fixed.
    /// - Returns: The response body. Empty for a 204.
    @discardableResult
    func send(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        guard let credentials else { throw PlatformAPIError.notConfigured }

        let accessToken = try await currentToken()

        var request = try makeRequest(
            method: method,
            path: path,
            query: query,
            credentials: credentials
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        var (data, response) = try await URLSession.shared.data(for: request)

        // A token can lapse between the expiry check and the call landing. Retry once with a
        // fresh token before reporting an authentication failure.
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            invalidateToken()
            let retryToken = try await currentToken()
            request.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PlatformAPIError.httpError(-1, nil)
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 400:
            throw PlatformAPIError.invalidRequest(Self.errorDetail(from: data))
        case 401:
            throw PlatformAPIError.authenticationFailed
        case 403:
            throw PlatformAPIError.forbidden
        case 404:
            throw PlatformAPIError.notFound
        case 409:
            throw PlatformAPIError.conflict(Self.errorDetail(from: data))
        case 415:
            throw PlatformAPIError.unsupportedMediaType
        default:
            throw PlatformAPIError.httpError(http.statusCode, Self.errorDetail(from: data))
        }
    }

    /// Sends a request and decodes the JSON body.
    func sendDecoding<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
        let data = try await send(
            method: method,
            path: path,
            query: query,
            body: body,
            contentType: contentType
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // The reason is included because without it a decode failure is undiagnosable: the
            // request succeeded, so there is no status code to go on. This describes structure
            // (which key, which type, where) and never response values.
            throw PlatformAPIError.decodingFailed(Self.decodingDetail(from: error))
        }
    }

    /// A short, structural description of a decode failure, for display.
    private static func decodingDetail(from error: Error) -> String? {
        guard let decodingError = error as? DecodingError else { return nil }

        func location(_ context: DecodingError.Context) -> String {
            let path = context.codingPath
                .map { $0.intValue.map(String.init) ?? $0.stringValue }
                .joined(separator: ".")
            return path.isEmpty ? "the top level" : "\u{201C}\(path)\u{201D}"
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "expected key \u{201C}\(key.stringValue)\u{201D} at \(location(context))"
        case .typeMismatch(let type, let context):
            return "wrong type at \(location(context)), expected \(type)"
        case .valueNotFound(let type, let context):
            return "null at \(location(context)) where \(type) was expected"
        case .dataCorrupted(let context):
            return "malformed data at \(location(context))"
        @unknown default:
            return nil
        }
    }

    // MARK: Token

    /// A valid access token, fetching or refreshing one if needed.
    private func currentToken() async throws -> String {
        if let token, let tokenExpiry, tokenExpiry.timeIntervalSinceNow > Self.refreshMargin {
            return token
        }

        if let refreshTask {
            return try await refreshTask.value.accessToken
        }

        guard let credentials else { throw PlatformAPIError.notConfigured }

        let task = Task<IssuedToken, Error> {
            try await Self.requestToken(for: credentials)
        }
        refreshTask = task

        do {
            let issued = try await task.value
            refreshTask = nil
            token = issued.accessToken
            tokenExpiry = Date().addingTimeInterval(issued.expiresIn)
            return issued.accessToken
        } catch {
            refreshTask = nil
            token = nil
            tokenExpiry = nil
            throw error
        }
    }

    /// Exchanges client credentials for an access token.
    ///
    /// The gateway uses `client_secret_post`, so the credentials go in the form body. The
    /// token endpoint sits on the same region host as the API calls — tokens are region-locked.
    private static func requestToken(for credentials: PlatformCredentials) async throws -> IssuedToken {
        guard let url = URL(string: "\(credentials.region.host)/auth/token") else {
            throw PlatformAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Built through URLComponents so a secret containing "+", "&" or "=" is encoded
        // correctly rather than corrupting the form body.
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientId),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Deliberately no detail here: a token error body can echo credential material.
            throw PlatformAPIError.authenticationFailed
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Double?
        }

        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw PlatformAPIError.authenticationFailed
        }

        return IssuedToken(
            accessToken: decoded.access_token,
            expiresIn: decoded.expires_in ?? 900
        )
    }

    private struct IssuedToken: Sendable {
        let accessToken: String
        let expiresIn: TimeInterval
    }

    // MARK: Helpers

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem],
        credentials: PlatformCredentials
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(credentials.region.host)/\(path)") else {
            throw PlatformAPIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw PlatformAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credentials.environmentId, forHTTPHeaderField: "X-Environment-Id")
        return request
    }

    /// Pulls a readable message out of an error body, preferring the gateway's structured
    /// fields and falling back to the raw text. Never logged — only returned for display.
    private static func errorDetail(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "detail", "description", "title", "errorMessage"] {
                if let value = object[key] as? String, !value.isEmpty {
                    return truncate(value)
                }
            }
            // Some gateway errors arrive as { "errors": [ { "description": "..." } ] }.
            if let errors = object["errors"] as? [[String: Any]] {
                let messages = errors.compactMap { entry -> String? in
                    for key in ["message", "description", "detail", "code"] {
                        if let value = entry[key] as? String, !value.isEmpty { return value }
                    }
                    return nil
                }
                if !messages.isEmpty { return truncate(messages.joined(separator: "; ")) }
            }
        }

        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return truncate(text)
    }

    private static func truncate(_ text: String) -> String {
        guard text.count > maxErrorDetailLength else { return text }
        return String(text.prefix(maxErrorDetailLength)) + "…"
    }
}
