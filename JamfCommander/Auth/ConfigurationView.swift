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
    /// Needed only for "Test Connection" on the Platform API section; the credential fields
    /// themselves are plain `@AppStorage`.
    @ObservedObject var api: JamfAPIService

    // MARK: Jamf Pro API (Classic + Pro endpoints)
    @AppStorage("jamfInstanceURL") private var instanceURL = "https://zellis.jamfcloud.com"
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

    /// Whether the Installomator sidebar hint may still appear.
    @AppStorage(SidebarHint.installomator.storageKey) private var showInstallomatorHint = true

    // Alert State
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var alertType: AlertType = .info

    /// Outcome of the last Platform API connection test.
    @State private var platformTest: PlatformTestState = .idle

    enum AlertType {
        case success, error, info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return .blue
            }
        }
    }

    enum PlatformTestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    private var hasPlatformSettings: Bool {
        !platformEnvironmentId.isEmpty || !platformClientId.isEmpty || !platformClientSecret.isEmpty
    }

    private var canTestPlatform: Bool {
        !platformEnvironmentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !platformClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !platformClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        generalSection
                    case .jamfConnections:
                        importExportSection
                        jamfProSection
                        platformSection
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

    // MARK: - Sections

    /// How the app behaves, as opposed to how it reaches Jamf. Currently one setting; it exists as
    /// its own tab because credentials and preferences are different kinds of thing and mixing them
    /// is how a settings sheet becomes a single unreadable column.
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Guidance", systemImage: "questionmark.bubble")
                .font(.headline)

            Text("Some modules explain themselves the first time you hover over them. Once dismissed they stay dismissed — bring them back here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installomator")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(showInstallomatorHint ? "Shown on hover" : "Dismissed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Show Again") {
                    showInstallomatorHint = true
                }
                .disabled(showInstallomatorHint)
                .help("Bring back the explanation that appears when you hover over Installomator")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    private var importExportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text("Import / Export Settings")
                    .font(.headline)
            }

            Text("Share your Jamf connection settings with team members using configuration files. Both sets of credentials below are included.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: importSettings) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Import settings from a .jamfconfig file")

                Button(action: exportSettings) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(instanceURL.isEmpty || clientId.isEmpty || clientSecret.isEmpty)
                .help("Export current settings to a .jamfconfig file")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    private var jamfProSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                Text("Jamf Pro API")
                    .font(.headline)
            }

            Text("An API client created in Jamf Pro. Used by every module except Blueprints.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading) {
                Text("Jamf Instance URL")
                    .font(.caption)
                TextField("https://...", text: $instanceURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Jamf Pro instance URL")
            }

            VStack(alignment: .leading) {
                Text("Client ID")
                    .font(.caption)
                TextField("e.g. 34065bc6-...", text: $clientId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Jamf Pro client ID")
            }

            VStack(alignment: .leading) {
                Text("Client Secret")
                    .font(.caption)
                SecureField("Paste Secret Here", text: $clientSecret)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Jamf Pro client secret")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.secondary)
                Text("Platform API — Blueprints")
                    .font(.headline)
            }

            Text("A separate integration, created in Jamf Account rather than Jamf Pro and scoped to a platform environment. A Jamf Pro API client cannot reach this API. Grant it the blueprints and device-groups capabilities.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading) {
                Text("Region")
                    .font(.caption)
                Picker("Region", selection: $platformRegion) {
                    ForEach(PlatformRegion.allCases) { region in
                        Text(region.displayName).tag(region.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Platform API region")
                Text("Must match where your Jamf instances are hosted — access tokens are region-locked.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Environment ID")
                    .font(.caption)
                TextField("e.g. cda24521-f23b-4f27-a9ff-32c89fb6feeb", text: $platformEnvironmentId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Platform environment ID")
                Text("Copied from the Integration details panel in Jamf Account.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Client ID")
                    .font(.caption)
                TextField("Integration client ID", text: $platformClientId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Platform API client ID")
            }

            VStack(alignment: .leading) {
                Text("Client Secret")
                    .font(.caption)
                SecureField("Paste Secret Here", text: $platformClientSecret)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Platform API client secret")
            }

            HStack(spacing: 10) {
                Button(action: testPlatformConnection) {
                    if platformTest == .testing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canTestPlatform || platformTest == .testing)
                .help("Request a token and list one blueprint, to confirm the credentials, region and environment ID")

                Spacer()
            }

            platformTestResult
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var platformTestResult: some View {
        switch platformTest {
        case .idle, .testing:
            EmptyView()
        case .succeeded:
            Label("Connected. Blueprints are reachable.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func testPlatformConnection() {
        platformTest = .testing
        Task {
            do {
                try await api.verifyPlatformConnection()
                platformTest = .succeeded
            } catch {
                platformTest = .failed(error.localizedDescription)
            }
        }
    }

    func importSettings() {
        let result = SettingsService.importSettings()

        switch result {
        case .success(let config):
            // Update all settings
            instanceURL = config.instanceURL
            clientId = config.clientId
            clientSecret = config.clientSecret

            // Platform values are optional in the file — a config written before Blueprints
            // existed leaves whatever is already stored alone rather than blanking it.
            if let region = config.platformRegion, PlatformRegion(rawValue: region) != nil {
                platformRegion = region
            }
            if let environmentId = config.platformEnvironmentId, !environmentId.isEmpty {
                platformEnvironmentId = environmentId
            }
            if let platformId = config.platformClientId, !platformId.isEmpty {
                platformClientId = platformId
            }
            if let platformSecret = config.platformClientSecret, !platformSecret.isEmpty {
                platformClientSecret = platformSecret
            }
            platformTest = .idle

            // Show success message
            alertType = .success
            alertTitle = "Import Successful"

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateString = formatter.string(from: config.exportDate)

            let includedPlatform = (config.platformClientId?.isEmpty == false)
            alertMessage = """
            Configuration imported successfully!

            Instance: \(config.instanceURL)
            Exported: \(dateString)
            Blueprints credentials: \(includedPlatform ? "included" : "not in this file")

            You can now connect to Jamf.
            """
            showAlert = true

        case .failure(let error):
            if case .userCancelled = error {
                return // Don't show alert for user cancellation
            }

            alertType = .error
            alertTitle = "Import Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    func exportSettings() {
        let result = SettingsService.exportSettings(
            instanceURL: instanceURL,
            clientId: clientId,
            clientSecret: clientSecret,
            platformRegion: platformRegion,
            platformEnvironmentId: platformEnvironmentId.isEmpty ? nil : platformEnvironmentId,
            platformClientId: platformClientId.isEmpty ? nil : platformClientId,
            platformClientSecret: platformClientSecret.isEmpty ? nil : platformClientSecret
        )

        switch result {
        case .success(let url):
            alertType = .success
            alertTitle = "Export Successful"
            alertMessage = """
            Configuration exported successfully!

            File saved to:
            \(url.path)

            Share this file with team members to quickly configure their Jamf Commander app.
            """
            showAlert = true

        case .failure(let error):
            if case .userCancelled = error {
                return // Don't show alert for user cancellation
            }

            alertType = .error
            alertTitle = "Export Failed"
            alertMessage = error.localizedDescription
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
        platformTest = .idle

        alertType = .info
        alertTitle = "Settings Cleared"
        alertMessage = "All configuration settings have been cleared."
        showAlert = true
    }
}
