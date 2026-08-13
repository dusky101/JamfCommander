//
//  ABMPrivateKey.swift
//  JamfCommander
//
//  Loading the Apple Business Manager signing key from the PEM file ABM issues.
//

import Foundation
import CryptoKit

/// Turns the `.pem` file downloaded from Apple Business Manager into a signing key.
///
/// ABM issues the key in **SEC1** form (`-----BEGIN EC PRIVATE KEY-----`). Python's JWT libraries
/// need it converted to PKCS#8 with `openssl pkcs8 -topk8` first, and CryptoKit's PEM initialiser
/// may not accept SEC1 either. Rather than ask every administrator to run openssl before they can
/// use the app — and get an opaque `invalid_client` when they forget — the conversion happens here.
///
/// Three attempts, cheapest first: whatever CryptoKit accepts natively, then the DER initialiser
/// (which handles PKCS#8), then a direct read of the SEC1 structure for the private scalar.
enum ABMPrivateKey {

    enum KeyError: LocalizedError {
        case notPEM
        case unsupportedFormat
        case wrongCurve
        case invalid

        var errorDescription: String? {
            switch self {
            case .notPEM:
                return "That file is not a PEM private key. Select the .pem file downloaded from Apple Business Manager."
            case .unsupportedFormat:
                return "The private key is in a format this app cannot read. It should be an EC private key issued by Apple Business Manager."
            case .wrongCurve:
                return "The private key is not on the P-256 curve. Apple Business Manager issues P-256 keys; this file is something else."
            case .invalid:
                return "The private key could not be read. It may be truncated or corrupted — download a fresh key from Apple Business Manager."
            }
        }
    }

    /// Parses PEM text into a P-256 signing key, or throws a message explaining what is wrong with it.
    static func parse(pem: String) throws -> P256.Signing.PrivateKey {
        // 1. Whatever CryptoKit accepts as PEM on this OS version.
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) {
            return key
        }

        let der = try derBytes(fromPEM: pem)

        // 2. The DER initialiser, which handles PKCS#8 ("BEGIN PRIVATE KEY").
        if let key = try? P256.Signing.PrivateKey(derRepresentation: der) {
            return key
        }

        // 3. SEC1 ("BEGIN EC PRIVATE KEY") — read the scalar out ourselves.
        let scalar = try sec1PrivateScalar(from: der)
        do {
            return try P256.Signing.PrivateKey(rawRepresentation: scalar)
        } catch {
            throw KeyError.invalid
        }
    }

    /// Validates a PEM without keeping the key, for the import flow.
    static func isValid(pem: String) -> Bool {
        (try? parse(pem: pem)) != nil
    }

    // MARK: - PEM

    /// Strips the armour lines and base64-decodes the body. Tolerates CRLF endings and trailing
    /// whitespace, both of which appear in files that have been through Windows or a paste buffer.
    private static func derBytes(fromPEM pem: String) throws -> Data {
        let lines = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard lines.contains(where: { $0.hasPrefix("-----BEGIN") }) else { throw KeyError.notPEM }

        let base64 = lines
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()

        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { throw KeyError.notPEM }
        return data
    }

    // MARK: - SEC1

    /// Reads the private scalar out of a SEC1 `ECPrivateKey`:
    ///
    ///     ECPrivateKey ::= SEQUENCE {
    ///       version        INTEGER { ecPrivkeyVer1(1) },
    ///       privateKey     OCTET STRING,
    ///       parameters [0] ECParameters OPTIONAL,
    ///       publicKey  [1] BIT STRING  OPTIONAL
    ///     }
    ///
    /// Only the first two fields are needed; the curve is confirmed by the scalar's length, since a
    /// P-256 scalar is exactly 32 bytes and no other curve Apple could issue is.
    private static func sec1PrivateScalar(from der: Data) throws -> Data {
        var reader = DERReader(bytes: [UInt8](der))

        guard try reader.readByte() == 0x30 else { throw KeyError.unsupportedFormat }
        _ = try reader.readLength()

        guard try reader.readByte() == 0x02 else { throw KeyError.unsupportedFormat }
        let versionLength = try reader.readLength()
        guard try reader.read(versionLength) == [0x01] else { throw KeyError.unsupportedFormat }

        guard try reader.readByte() == 0x04 else { throw KeyError.unsupportedFormat }
        let scalarLength = try reader.readLength()
        let scalar = try reader.read(scalarLength)

        guard scalar.count == 32 else { throw KeyError.wrongCurve }
        return Data(scalar)
    }

    /// A deliberately minimal DER reader: enough to walk the two fields above, and nothing more.
    private struct DERReader {
        private let bytes: [UInt8]
        private var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func readByte() throws -> UInt8 {
            guard index < bytes.count else { throw KeyError.unsupportedFormat }
            defer { index += 1 }
            return bytes[index]
        }

        /// DER length: a single byte below 0x80, otherwise the low seven bits give how many
        /// big-endian length bytes follow.
        mutating func readLength() throws -> Int {
            let first = try readByte()
            guard first >= 0x80 else { return Int(first) }

            let byteCount = Int(first & 0x7F)
            guard byteCount > 0, byteCount <= 4 else { throw KeyError.unsupportedFormat }

            var length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(try readByte())
            }
            return length
        }

        mutating func read(_ count: Int) throws -> [UInt8] {
            guard count >= 0, index + count <= bytes.count else { throw KeyError.unsupportedFormat }
            defer { index += count }
            return Array(bytes[index..<(index + count)])
        }
    }
}
