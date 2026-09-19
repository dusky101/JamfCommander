//
//  SettingsTransfer.swift
//  JamfCommander
//
//  Created by Marc Oliff on 19/09/2026.
//

import Foundation

// MARK: - Credentials

/// Every credential one connection needs: the Jamf Pro API client used by most of the app, and the
/// separate Platform API integration that Blueprints requires.
///
/// Gathered into one value so a transfer is a single call rather than seven loose strings threaded
/// through the Settings view. All of it is secret — see root `CLAUDE.md`, invariant 4 — so nothing
/// here is ever logged or put into an alert beyond the instance URL.
nonisolated struct JamfCredentials: Sendable {
    var instanceURL: String
    var clientId: String
    var clientSecret: String

    var platformRegion: String
    var platformEnvironmentId: String
    var platformClientId: String
    var platformClientSecret: String
}

// MARK: - Transfer

/// Moves credentials in and out of `.jamfconfig` files on behalf of Settings.
///
/// `SettingsService` owns the file itself: the save and open panels, the encoding, the signature
/// check. This owns what a transfer *means* — which stored values survive a file written before
/// Blueprints existed, and what the administrator is told afterwards. `ConfigurationView` is left
/// with applying the result to its stored settings, which is the only part of this that belongs in
/// a view.
///
/// Main-actor isolated by default, as `SettingsService` is, because both run a modal panel.
enum SettingsTransfer {

    /// What to show once a transfer has finished. Carries the instance URL on a successful import,
    /// as the Settings screen has always done, and never a client ID, a secret or a token.
    struct Outcome {
        let title: String
        let message: String
    }

    /// The result of an import. `cancelled` is a separate case because dismissing the open panel is
    /// not a failure and must not raise an alert.
    enum ImportResult {
        /// Store these credentials, then show the outcome.
        case imported(JamfCredentials, Outcome)
        case cancelled
        case failed(Outcome)
    }

    /// The result of an export, treating a dismissed save panel the same way.
    enum ExportResult {
        case exported(Outcome)
        case cancelled
        case failed(Outcome)
    }

    // MARK: - Import

    /// Reads a `.jamfconfig` and returns the credentials to store.
    ///
    /// Merged onto `current` rather than replacing it outright: the Platform API values are optional
    /// in the file, so a configuration written before Blueprints existed leaves whatever is already
    /// stored alone rather than blanking a working integration.
    static func importConfiguration(mergingInto current: JamfCredentials) -> ImportResult {
        switch SettingsService.importSettings() {
        case .success(let config):
            var merged = current
            merged.instanceURL = config.instanceURL
            merged.clientId = config.clientId
            merged.clientSecret = config.clientSecret

            // An unrecognised region is ignored rather than stored: tokens are region-locked, and a
            // region the app cannot map would fail every Blueprints call with a 401.
            if let region = config.platformRegion, PlatformRegion(rawValue: region) != nil {
                merged.platformRegion = region
            }
            if let environmentId = config.platformEnvironmentId, !environmentId.isEmpty {
                merged.platformEnvironmentId = environmentId
            }
            if let platformId = config.platformClientId, !platformId.isEmpty {
                merged.platformClientId = platformId
            }
            if let platformSecret = config.platformClientSecret, !platformSecret.isEmpty {
                merged.platformClientSecret = platformSecret
            }

            let includedPlatform = (config.platformClientId?.isEmpty == false)
            let outcome = Outcome(
                title: "Import Successful",
                message: """
                Configuration imported successfully!

                Instance: \(config.instanceURL)
                Exported: \(exportedDescription(config.exportDate))
                Blueprints credentials: \(includedPlatform ? "included" : "not in this file")

                You can now connect to Jamf.
                """
            )
            return .imported(merged, outcome)

        case .failure(.userCancelled):
            return .cancelled

        case .failure(let error):
            return .failed(Outcome(title: "Import Failed", message: error.localizedDescription))
        }
    }

    // MARK: - Export

    /// Writes the stored credentials to a `.jamfconfig`.
    ///
    /// Empty Platform API values are sent as `nil` so the file omits them altogether, rather than
    /// recording blanks that would read as "this integration is deliberately empty" on the machine
    /// that imports it.
    static func exportConfiguration(_ credentials: JamfCredentials) -> ExportResult {
        let result = SettingsService.exportSettings(
            instanceURL: credentials.instanceURL,
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret,
            platformRegion: credentials.platformRegion,
            platformEnvironmentId: nilIfEmpty(credentials.platformEnvironmentId),
            platformClientId: nilIfEmpty(credentials.platformClientId),
            platformClientSecret: nilIfEmpty(credentials.platformClientSecret)
        )

        switch result {
        case .success(let url):
            let outcome = Outcome(
                title: "Export Successful",
                message: """
                Configuration exported successfully!

                File saved to:
                \(url.path)

                Share this file with team members to quickly configure their Jamf Commander app.
                """
            )
            return .exported(outcome)

        case .failure(.userCancelled):
            return .cancelled

        case .failure(let error):
            return .failed(Outcome(title: "Export Failed", message: error.localizedDescription))
        }
    }

    // MARK: - Helpers

    private static func nilIfEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    /// How the exported-on date reads in the import confirmation.
    private static func exportedDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
