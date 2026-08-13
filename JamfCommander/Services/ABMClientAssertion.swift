//
//  ABMClientAssertion.swift
//  JamfCommander
//
//  ES256 client assertions for the Apple Business Manager token exchange.
//

import Foundation
import CryptoKit

/// Builds the short-lived ES256 JWT that Apple Business Manager exchanges for an access token.
///
/// Assertions are generated fresh for every token request and never written to disk. Apple permits
/// an expiry up to 180 days out, but an assertion is a bearer credential granting full access to the
/// organisation — there is no reason for one to outlive the request it was made for.
enum ABMClientAssertion {

    /// The `aud` claim contains `/v2/`; the URL the assertion is POSTed to does not. This is genuinely
    /// how the service behaves, and getting it wrong returns a bare `invalid_client` with no
    /// indication of the cause. Do not "fix" this to match `ABMEndpoints.token`.
    static let audience = "https://account.apple.com/auth/oauth2/v2/token"

    /// Fifteen minutes: long enough to survive a slow request, short enough to be worthless if leaked.
    static let lifetime: TimeInterval = 900

    enum AssertionError: LocalizedError {
        case encodingFailed
        case signingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "The Apple Business Manager client assertion could not be built."
            case .signingFailed:
                return "The Apple Business Manager client assertion could not be signed with the stored private key."
            }
        }
    }

    /// - Parameters:
    ///   - clientId: the ABM client ID, used as **both** `iss` and `sub`. Apple's sample code calls
    ///     this a team identifier, which is misleading — ABM has no separate team.
    ///   - keyId: the ABM key ID, carried in the JWT header as `kid`.
    ///   - privateKeyPEM: the PEM text of the ABM private key.
    static func make(clientId: String, keyId: String, privateKeyPEM: String) throws -> String {
        let key = try ABMPrivateKey.parse(pem: privateKeyPEM)
        let now = Int(Date().timeIntervalSince1970)

        let header: [String: Any] = [
            "alg": "ES256",
            "kid": keyId
        ]

        let payload: [String: Any] = [
            "sub": clientId,
            "iss": clientId,
            "aud": audience,
            "iat": now,
            "exp": now + Int(lifetime),
            "jti": UUID().uuidString
        ]

        let signingInput = "\(try encodeSegment(header)).\(try encodeSegment(payload))"

        let signature: P256.Signing.ECDSASignature
        do {
            // `signature(for:)` computes the SHA-256 digest itself. Hashing first would produce a
            // valid signature over the wrong data, which also fails as a bare `invalid_client`.
            signature = try key.signature(for: Data(signingInput.utf8))
        } catch {
            throw AssertionError.signingFailed
        }

        // JWS ES256 wants r ‖ s as 64 raw bytes. `derRepresentation` is ASN.1-wrapped and Apple
        // rejects it with no explanation, so this must stay `rawRepresentation`.
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    // MARK: - Encoding

    private static func encodeSegment(_ object: [String: Any]) throws -> String {
        // `.sortedKeys` keeps the output deterministic; `.withoutEscapingSlashes` keeps the `aud`
        // URL readable rather than shipping escaped separators.
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            throw AssertionError.encodingFailed
        }
        return base64URL(data)
    }

    /// Base64URL without padding, which Foundation does not provide directly.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
