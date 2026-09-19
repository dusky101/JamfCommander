//
//  ConfigurationView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//


import SwiftUI
import Combine

/// Opens Settings from anywhere.
///
/// Shared rather than local state because Settings is reachable from two places that know nothing
/// about each other: the sidebar footer, and the standard Settings item in the application menu
/// (⌘,), which macOS expects every app to have and which lives in the `App` scene.
@MainActor
final class SettingsPresenter: ObservableObject {
    static let shared = SettingsPresenter()
    private init() {}

    @Published var isPresented = false
    /// Which tab Settings opens on. Somebody who has just pressed a button about connecting to Jamf
    /// should land on the credentials, not on application preferences.
    @Published var initialTab: SettingsTab = .general

    func present(_ tab: SettingsTab) {
        initialTab = tab
        isPresented = true
    }
}

/// The two halves of Settings: how the app behaves, and how it reaches Jamf.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case jamfConnections = "Jamf Connections"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .jamfConnections: return "key.horizontal"
        }
    }
}

struct ConfigurationView: View {
    /// Passed straight through to `SettingsPlatformSection` for its "Test Connection" button, which
    /// is the only part of Settings that calls Jamf. Every credential field is plain `@AppStorage`.
    @ObservedObject var api: JamfAPIService

    // MARK: Jamf Pro API (Classic + Pro endpoints)
    @AppStorage("jamfInstanceURL") private var instanceURL = ""
    @AppStorage("clientId") private var clientId = ""
    @AppStorage("clientSecret") private var clientSecret = ""

    // MARK: Platform API Gateway (blueprints)
    @AppStorage(PlatformCredentialsStore.regionKey) private var platformRegion = PlatformRegion.eu.rawValue
    @AppStorage(PlatformCredentialsStore.environmentIdKey) private var platformEnvironmentId = ""
    @AppStorage(PlatformCredentialsStore.clientIdKey) private var platformClientId = ""
    @AppStorage(PlatformCredentialsStore.clientSecretKey) private var platformClientSecret = ""

    @Environment(\.dismiss) var dismiss

    @ObservedObject private var presenter = SettingsPresenter.shared
    @State private var tab: SettingsTab = .general

    // Alert State
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var hasPlatformSettings: Bool {
        !platformEnvironmentId.isEmpty || !platformClientId.isEmpty || !platformClientSecret.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)

                Picker("", selection: $tab) {
                    ForEach(SettingsTab.allCases) { option in
                        Label(option.rawValue, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .general:
                        SettingsGeneralSection()
                    case .jamfConnections:
                        SettingsTransferSection(onImport: importSettings, onExport: exportSettings)
                        SettingsJamfProSection()
                        SettingsPlatformSection(api: api)
                    }
                }
                .padding()
            }

            Divider()

            // Footer Buttons
            HStack {
                // Clear All Button
                if tab == .jamfConnections,
                   !instanceURL.isEmpty || !clientId.isEmpty || !clientSecret.isEmpty || hasPlatformSettings {
                    Button(action: clearAllSettings) {
                        Label("Clear All", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove every stored credential, for both APIs")
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 720)
        .appBackground()
        .onAppear { tab = presenter.initialTab }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Actions

    /// The credentials exactly as Settings currently holds them.
    private var storedCredentials: JamfCredentials {
        JamfCredentials(
            instanceURL: instanceURL,
            clientId: clientId,
            clientSecret: clientSecret,
            platformRegion: platformRegion,
            platformEnvironmentId: platformEnvironmentId,
            platformClientId: platformClientId,
            platformClientSecret: platformClientSecret
        )
    }

    private func store(_ credentials: JamfCredentials) {
        instanceURL = credentials.instanceURL
        clientId = credentials.clientId
        clientSecret = credentials.clientSecret
        platformRegion = credentials.platformRegion
        platformEnvironmentId = credentials.platformEnvironmentId
        platformClientId = credentials.platformClientId
        platformClientSecret = credentials.platformClientSecret
    }

    func importSettings() {
        switch SettingsTransfer.importConfiguration(mergingInto: storedCredentials) {
        case .imported(let credentials, let outcome):
            // Storing the credentials is enough to clear a stale Platform test result: the section
            // watches those values. A file carrying no Platform values changes nothing there, and
            // a result obtained for the integration still in place stays valid.
            store(credentials)

            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true

        case .cancelled:
            return // Dismissing the open panel is not a failure.

        case .failed(let outcome):
            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true
        }
    }

    func exportSettings() {
        switch SettingsTransfer.exportConfiguration(storedCredentials) {
        case .exported(let outcome):
            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true

        case .cancelled:
            return // Dismissing the save panel is not a failure.

        case .failed(let outcome):
            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true
        }
    }

    func clearAllSettings() {
        instanceURL = ""
        clientId = ""
        clientSecret = ""

        platformEnvironmentId = ""
        platformClientId = ""
        platformClientSecret = ""
        platformRegion = PlatformRegion.eu.rawValue
        // Emptying the Platform fields clears any test result on its own — the section watches them.

        alertTitle = "Settings Cleared"
        alertMessage = "All configuration settings have been cleared."
        showAlert = true
    }
}
