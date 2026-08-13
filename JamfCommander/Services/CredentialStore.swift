//
//  CredentialStore.swift
//  JamfCommander
//
//  The single source of truth for the Jamf API credentials.
//

import Foundation
import Combine

/// Holds the Jamf client ID and secret, backed by the Keychain.
///
/// Views observe this instead of reading the Keychain themselves, so they still update reactively
/// the way `@AppStorage` did before the credentials moved out of `UserDefaults`.
///
/// The **instance URL deliberately stays in `UserDefaults`** under `jamfInstanceURL`. It is an
/// endpoint, not a secret, and several views read it directly to build "open in Jamf" links.
///
/// Shared rather than injected, matching `HelpPresenter.shared` — the credentials are genuinely
/// app-wide state and are read from three unrelated points in the view tree.
final class CredentialStore: ObservableObject {

    static let shared = CredentialStore()

    /// `UserDefaults` keys used by builds before the credentials moved to the Keychain. Read once at
    /// launch so an existing install keeps working, then removed.
    private enum Legacy {
        static let clientId = "clientId"
        static let clientSecret = "clientSecret"
    }

    @Published var clientId: String {
        didSet {
            guard clientId != oldValue else { return }
            persist(clientId, as: .jamfClientId)
        }
    }

    @Published var clientSecret: String {
        didSet {
            guard clientSecret != oldValue else { return }
            persist(clientSecret, as: .jamfClientSecret)
        }
    }

    // MARK: - Apple Business Manager

    @Published var abmClientId: String {
        didSet {
            guard abmClientId != oldValue else { return }
            persist(abmClientId, as: .abmClientId)
            ABMAPIService.shared.invalidateSession()
        }
    }

    @Published var abmKeyId: String {
        didSet {
            guard abmKeyId != oldValue else { return }
            persist(abmKeyId, as: .abmKeyId)
            ABMAPIService.shared.invalidateSession()
        }
    }

    /// Whether a private key is stored. The key itself is never published — it is read from the
    /// Keychain only to sign an assertion, and is never displayed or bound to a control.
    @Published private(set) var hasABMPrivateKey: Bool

    /// The most recent Keychain failure, in British English and free of credential content, for the
    /// configuration sheet to surface. `nil` when everything is healthy.
    @Published private(set) var lastError: String?

    /// Whether both halves of the credential are present. The instance URL is checked separately by
    /// the callers that need it.
    var hasCredentials: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }

    /// Whether Apple Business Manager can be reached: all three parts are needed to sign an assertion.
    var hasABMCredentials: Bool {
        !abmClientId.isEmpty && !abmKeyId.isEmpty && hasABMPrivateKey
    }

    private init() {
        let loaded = Self.loadCredentials()
        // Assigned during initialisation, so the `didSet` write-through does not fire and we do not
        // immediately write back what we have just read.
        self.clientId = loaded.clientId
        self.clientSecret = loaded.clientSecret
        self.abmClientId = loaded.abmClientId
        self.abmKeyId = loaded.abmKeyId
        self.hasABMPrivateKey = loaded.hasABMPrivateKey
        self.lastError = loaded.error
    }

    // MARK: - ABM private key

    /// Validates PEM text and stores it. Rejects anything that is not a P-256 private key, so a wrong
    /// file is caught at import rather than surfacing later as an opaque `invalid_client`.
    func importABMPrivateKey(pem: String) throws {
        _ = try ABMPrivateKey.parse(pem: pem)

        do {
            try KeychainStore.set(pem, for: .abmPrivateKey)
            hasABMPrivateKey = true
            lastError = nil
            ABMAPIService.shared.invalidateSession()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func removeABMPrivateKey() {
        do {
            try KeychainStore.remove(.abmPrivateKey)
            hasABMPrivateKey = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        ABMAPIService.shared.invalidateSession()
    }

    /// The stored PEM, for signing only. Never log, display, or write this anywhere.
    func abmPrivateKeyPEM() -> String? {
        try? KeychainStore.string(for: .abmPrivateKey)
    }

    func clearABMCredentials() {
        abmClientId = ""
        abmKeyId = ""
        removeABMPrivateKey()
    }

    // MARK: - Mutation

    /// Clears every credential this app holds, Jamf and Apple Business Manager alike, from memory and
    /// the Keychain. Used by "Clear All".
    func clearAll() {
        clientId = ""
        clientSecret = ""
        abmClientId = ""
        abmKeyId = ""
        hasABMPrivateKey = false

        do {
            try KeychainStore.removeAll()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        ABMAPIService.shared.invalidateSession()
    }

    /// Applies an imported configuration in one step, so a partial import cannot leave the client ID
    /// and secret belonging to different instances.
    func apply(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    // MARK: - Persistence

    private func persist(_ value: String, as key: KeychainStore.Key) {
        do {
            try KeychainStore.set(value, for: key)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Loading & migration

    private struct LoadResult {
        var clientId: String
        var clientSecret: String
        var error: String?

        // Apple Business Manager. Never migrated from UserDefaults — these have only ever lived in
        // the Keychain.
        var abmClientId: String = ""
        var abmKeyId: String = ""
        var hasABMPrivateKey: Bool = false
    }

    /// Reads the credentials from the Keychain, adopting any left behind by a pre-Keychain build.
    ///
    /// The legacy `UserDefaults` values are only removed once they have been written to the Keychain
    /// **and** read back successfully. If the Keychain is unavailable the old values are kept where
    /// they are and used in memory, so a failure here degrades to the previous behaviour rather than
    /// locking someone out of their own instance.
    private static func loadCredentials() -> LoadResult {
        var result = loadJamfCredentials()
        applyABMCredentials(to: &result)
        return result
    }

    private static func loadJamfCredentials() -> LoadResult {
        do {
            let storedId = try KeychainStore.string(for: .jamfClientId) ?? ""
            let storedSecret = try KeychainStore.string(for: .jamfClientSecret) ?? ""

            if !storedId.isEmpty || !storedSecret.isEmpty {
                removeLegacyValues()
                return LoadResult(clientId: storedId, clientSecret: storedSecret, error: nil)
            }

            return migrateLegacyValues()
        } catch {
            return LoadResult(
                clientId: UserDefaults.standard.string(forKey: Legacy.clientId) ?? "",
                clientSecret: UserDefaults.standard.string(forKey: Legacy.clientSecret) ?? "",
                error: error.localizedDescription
            )
        }
    }

    /// Reads the ABM credentials. A failure here is reported but does not disturb the Jamf side —
    /// losing ABM enrichment is an inconvenience; losing the Jamf connection is not.
    private static func applyABMCredentials(to result: inout LoadResult) {
        do {
            result.abmClientId = try KeychainStore.string(for: .abmClientId) ?? ""
            result.abmKeyId = try KeychainStore.string(for: .abmKeyId) ?? ""
            result.hasABMPrivateKey = try KeychainStore.string(for: .abmPrivateKey) != nil
        } catch {
            result.error = result.error ?? error.localizedDescription
        }
    }

    private static func migrateLegacyValues() -> LoadResult {
        let defaults = UserDefaults.standard
        let legacyId = defaults.string(forKey: Legacy.clientId) ?? ""
        let legacySecret = defaults.string(forKey: Legacy.clientSecret) ?? ""

        guard !legacyId.isEmpty || !legacySecret.isEmpty else {
            return LoadResult(clientId: "", clientSecret: "", error: nil)
        }

        do {
            try KeychainStore.set(legacyId, for: .jamfClientId)
            try KeychainStore.set(legacySecret, for: .jamfClientSecret)

            // Verify the round trip before deleting the only other copy.
            let verifiedId = try KeychainStore.string(for: .jamfClientId) ?? ""
            let verifiedSecret = try KeychainStore.string(for: .jamfClientSecret) ?? ""

            guard verifiedId == legacyId, verifiedSecret == legacySecret else {
                return LoadResult(
                    clientId: legacyId,
                    clientSecret: legacySecret,
                    error: "Credentials could not be verified in the Keychain and remain in the previous store."
                )
            }

            removeLegacyValues()
            return LoadResult(clientId: legacyId, clientSecret: legacySecret, error: nil)
        } catch {
            return LoadResult(clientId: legacyId, clientSecret: legacySecret, error: error.localizedDescription)
        }
    }

    private static func removeLegacyValues() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Legacy.clientId)
        defaults.removeObject(forKey: Legacy.clientSecret)
    }
}
