//
//  SettingsService.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import AppKit
import CryptoKit
import CommonCrypto
import UniformTypeIdentifiers

/// Service for importing and exporting Jamf Commander settings.
///
/// Creates `.jamfconfig` files that can be shared between team members. The file carries a working
/// API client secret, so from format **v2** it is encrypted with AES-GCM under a key derived from a
/// passphrase the exporter chooses; the passphrase must reach the recipient by a different route
/// from the file itself.
///
/// Format v1 — a header line plus base64 of the plain JSON — is still **read** so existing files keep
/// working, but is never written. Base64 is transport encoding, not protection: a v1 file hands its
/// client secret to anyone who opens it.
struct SettingsService {

    // MARK: - File format

    /// Written by this build. Encrypted payload.
    private static let currentHeader = "JAMF_COMMANDER_CONFIG_V2"
    /// Written by builds before encryption was added. Still readable.
    private static let legacyHeader = "JAMF_COMMANDER_CONFIG"

    private static let envelopeSignature = "JamfCommander-v2"
    private static let payloadSignature = "JamfCommander-v1"

    /// OWASP's guidance for PBKDF2-HMAC-SHA256. Stored in the envelope so a future increase can still
    /// open today's files.
    private static let pbkdf2Iterations = 600_000
    private static let saltLength = 16
    private static let derivedKeyLength = 32

    private static let minimumPassphraseLength = 8

    // MARK: - Models

    /// The decrypted payload. Its `signature` validates the *payload* shape; the envelope's separate
    /// signature validates the *file format*.
    struct JamfConfiguration: Codable {
        let instanceURL: String
        let clientId: String
        let clientSecret: String
        let exportDate: Date
        let appVersion: String
        let signature: String

        // Custom initializer for creating new configurations
        init(instanceURL: String, clientId: String, clientSecret: String, exportDate: Date, appVersion: String) {
            self.instanceURL = instanceURL
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.exportDate = exportDate
            self.appVersion = appVersion
            self.signature = SettingsService.payloadSignature
        }
    }

    /// The on-disk wrapper around the encrypted payload. Everything the reader needs to derive the
    /// same key, and nothing that duplicates the payload — a field held outside the sealed box would
    /// be unauthenticated and could be edited without detection.
    private struct EncryptedEnvelope: Codable {
        let signature: String
        let salt: Data
        let iterations: Int
        /// AES-GCM combined representation: nonce ‖ ciphertext ‖ tag.
        let sealedBox: Data
    }

    // MARK: - Export

    /// Export current settings to an encrypted `.jamfconfig` file.
    /// - Parameters:
    ///   - instanceURL: The Jamf instance URL
    ///   - clientId: API Client ID
    ///   - clientSecret: API Client Secret
    /// - Returns: The saved file's location, or the reason it was not written.
    static func exportSettings(instanceURL: String, clientId: String, clientSecret: String) -> Result<URL, SettingsError> {
        // Ask for the passphrase first: there is no point building a payload the user then abandons.
        let passphrase: String
        switch promptForNewPassphrase() {
        case .success(let value):
            passphrase = value
        case .failure(let error):
            return .failure(error)
        }

        let config = JamfConfiguration(
            instanceURL: instanceURL,
            clientId: clientId,
            clientSecret: clientSecret,
            exportDate: Date(),
            appVersion: appVersion
        )

        let fileContent: String
        do {
            let payload = try JSONEncoder().encode(config)
            let envelope = try seal(payload: payload, passphrase: passphrase)
            let envelopeData = try JSONEncoder().encode(envelope)
            fileContent = "\(currentHeader)\n\(envelopeData.base64EncodedString())"
        } catch let error as SettingsError {
            return .failure(error)
        } catch {
            return .failure(.encodingFailed)
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Jamf Configuration"
        savePanel.message = "Save your Jamf connection settings to share with team members. The file is encrypted with the passphrase you entered."
        savePanel.nameFieldStringValue = "JamfConfig-\(formatDate()).jamfconfig"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "jamfconfig") ?? .data]
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return .failure(.userCancelled)
        }

        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            return .success(url)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    // MARK: - Import

    /// Import settings from a `.jamfconfig` file. Handles both the encrypted v2 format and the
    /// unencrypted v1 files earlier builds produced.
    /// - Returns: Result with configuration or error
    static func importSettings() -> Result<JamfConfiguration, SettingsError> {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Jamf Configuration"
        openPanel.message = "Select a .jamfconfig file to import settings."
        openPanel.allowedContentTypes = [UTType(filenameExtension: "jamfconfig") ?? .data]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return .failure(.userCancelled)
        }

        guard let fileContent = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure(.readFailed)
        }

        let lines = fileContent.components(separatedBy: "\n")
        guard lines.count >= 2 else { return .failure(.invalidFileFormat) }

        let header = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)

        switch header {
        case currentHeader:
            return importEncrypted(body: body)
        case legacyHeader:
            return importLegacy(body: body)
        default:
            return .failure(.invalidFileFormat)
        }
    }

    private static func importEncrypted(body: String) -> Result<JamfConfiguration, SettingsError> {
        guard let envelopeData = Data(base64Encoded: body),
              let envelope = try? JSONDecoder().decode(EncryptedEnvelope.self, from: envelopeData) else {
            return .failure(.decodingFailed)
        }

        guard envelope.signature == envelopeSignature else {
            return .failure(.invalidSignature)
        }

        let passphrase: String
        switch promptForPassphrase() {
        case .success(let value):
            passphrase = value
        case .failure(let error):
            return .failure(error)
        }

        do {
            let payload = try open(envelope: envelope, passphrase: passphrase)
            let config = try JSONDecoder().decode(JamfConfiguration.self, from: payload)
            guard config.signature == payloadSignature else { return .failure(.invalidSignature) }
            return .success(config)
        } catch let error as SettingsError {
            return .failure(error)
        } catch {
            // A wrong passphrase surfaces here as an authentication failure from AES-GCM, which is
            // indistinguishable from a tampered file — and is reported as such.
            return .failure(.decryptionFailed)
        }
    }

    private static func importLegacy(body: String) -> Result<JamfConfiguration, SettingsError> {
        guard let jsonData = Data(base64Encoded: body) else {
            return .failure(.decodingFailed)
        }

        do {
            let config = try JSONDecoder().decode(JamfConfiguration.self, from: jsonData)
            guard config.signature == payloadSignature else {
                return .failure(.invalidSignature)
            }
            return .success(config)
        } catch {
            return .failure(.decodingFailed)
        }
    }

    // MARK: - Apple Business Manager private key

    /// Presents a file picker for the ABM private key and returns its PEM text.
    ///
    /// The file's location is deliberately **not** retained: the key is copied into the Keychain by
    /// `CredentialStore`, and the downloaded `.pem` should then be deleted. Apple issues it once.
    static func importABMPrivateKeyFile() -> Result<String, SettingsError> {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Apple Business Manager Private Key"
        openPanel.message = "Select the private key file downloaded from Apple Business Manager."
        // The download is not reliably given a .pem extension, so any file may be chosen; an
        // incorrect one is rejected by validation rather than by the picker.
        openPanel.allowedContentTypes = [UTType(filenameExtension: "pem") ?? .data, .data]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return .failure(.userCancelled)
        }

        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure(.readFailed)
        }

        return .success(contents)
    }

    // MARK: - Encryption

    private static func seal(payload: Data, passphrase: String) throws -> EncryptedEnvelope {
        var salt = Data(count: saltLength)
        let result = salt.withUnsafeMutableBytes { buffer -> Int32 in
            guard let address = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, saltLength, address)
        }
        guard result == errSecSuccess else { throw SettingsError.encodingFailed }

        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: pbkdf2Iterations)
        let box = try AES.GCM.seal(payload, using: key)
        guard let combined = box.combined else { throw SettingsError.encodingFailed }

        return EncryptedEnvelope(
            signature: envelopeSignature,
            salt: salt,
            iterations: pbkdf2Iterations,
            sealedBox: combined
        )
    }

    private static func open(envelope: EncryptedEnvelope, passphrase: String) throws -> Data {
        let key = try deriveKey(
            passphrase: passphrase,
            salt: envelope.salt,
            iterations: envelope.iterations
        )
        let box = try AES.GCM.SealedBox(combined: envelope.sealedBox)
        return try AES.GCM.open(box, using: key)
    }

    /// PBKDF2-HMAC-SHA256. A passphrase is low-entropy, so the derivation is deliberately slow —
    /// this is what stands between a leaked file and its client secret.
    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard iterations > 0 else { throw SettingsError.decryptionFailed }

        let passphraseLength = passphrase.utf8.count
        var derived = Data(count: derivedKeyLength)

        let status = derived.withUnsafeMutableBytes { derivedBuffer -> Int32 in
            salt.withUnsafeBytes { saltBuffer -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase,
                    passphraseLength,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                    derivedKeyLength
                )
            }
        }

        guard status == kCCSuccess else { throw SettingsError.decryptionFailed }
        return SymmetricKey(data: derived)
    }

    // MARK: - Passphrase prompts

    /// Asks for a new passphrase twice, so a typo does not produce a file nobody can open.
    private static func promptForNewPassphrase() -> Result<String, SettingsError> {
        let alert = NSAlert()
        alert.messageText = "Choose a Passphrase"
        alert.informativeText = """
        The exported file contains your Jamf API client secret and is encrypted with this passphrase. \
        Send the passphrase to your colleagues separately from the file itself.

        Minimum \(minimumPassphraseLength) characters. It cannot be recovered if forgotten.
        """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))

        let passphraseField = NSSecureTextField(frame: NSRect(x: 0, y: 32, width: 300, height: 24))
        passphraseField.placeholderString = "Passphrase"
        container.addSubview(passphraseField)

        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        confirmField.placeholderString = "Confirm passphrase"
        container.addSubview(confirmField)

        alert.accessoryView = container
        alert.window.initialFirstResponder = passphraseField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .failure(.userCancelled)
        }

        let passphrase = passphraseField.stringValue
        guard passphrase.count >= minimumPassphraseLength else {
            return .failure(.passphraseTooShort(minimumPassphraseLength))
        }
        guard passphrase == confirmField.stringValue else {
            return .failure(.passphraseMismatch)
        }

        return .success(passphrase)
    }

    private static func promptForPassphrase() -> Result<String, SettingsError> {
        let alert = NSAlert()
        alert.messageText = "Enter the Passphrase"
        alert.informativeText = "This configuration file is encrypted. Enter the passphrase you were given by whoever exported it."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let passphraseField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        passphraseField.placeholderString = "Passphrase"
        alert.accessoryView = passphraseField
        alert.window.initialFirstResponder = passphraseField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return .failure(.userCancelled)
        }

        let passphrase = passphraseField.stringValue
        guard !passphrase.isEmpty else { return .failure(.userCancelled) }

        return .success(passphrase)
    }

    // MARK: - Helpers

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private static func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Error Types

    enum SettingsError: LocalizedError {
        case encodingFailed
        case decodingFailed
        case decryptionFailed
        case passphraseTooShort(Int)
        case passphraseMismatch
        case writeFailed(String)
        case readFailed
        case invalidFileFormat
        case invalidSignature
        case userCancelled

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode configuration data."
            case .decodingFailed:
                return "Failed to decode configuration file. The file may be corrupted."
            case .decryptionFailed:
                return "Could not decrypt the configuration file. The passphrase may be wrong, or the file may have been altered since it was exported."
            case .passphraseTooShort(let minimum):
                return "The passphrase must be at least \(minimum) characters."
            case .passphraseMismatch:
                return "The two passphrases do not match."
            case .writeFailed(let details):
                return "Failed to write configuration file: \(details)"
            case .readFailed:
                return "Failed to read configuration file."
            case .invalidFileFormat:
                return "Invalid file format. This doesn't appear to be a Jamf Commander configuration file."
            case .invalidSignature:
                return "Invalid file signature. This file may have been created by a different version."
            case .userCancelled:
                return "Operation cancelled by user."
            }
        }
    }
}
