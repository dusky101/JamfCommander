//
//  ConfigurationView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//


import SwiftUI

struct ConfigurationView: View {
    // The instance URL is an endpoint rather than a secret, so it stays in UserDefaults where the
    // "open in Jamf" links can read it. The client ID and secret live in the Keychain.
    @AppStorage("jamfInstanceURL") private var instanceURL = "https://zellis.jamfcloud.com"
    @ObservedObject private var credentials = CredentialStore.shared
    @ObservedObject private var fleet = ABMFleetStore.shared

    // Apple Business Manager settings. Neither is a secret: the MDM server identifier scopes the
    // fetch, and the lifecycle interval is a local preference.
    @AppStorage("abmMDMServerId") private var abmMDMServerId = ""
    @AppStorage("abmLifecycleYears") private var abmLifecycleYears = 4

    @Environment(\.dismiss) var dismiss

    /// 0 = Jamf Pro, 1 = Apple Business Manager.
    @State private var selectedSection = 0

    // ABM connection test state
    @State private var isTestingABM = false
    @State private var abmTestResult: ABMTestOutcome?

    struct ABMTestOutcome {
        let isSuccess: Bool
        let message: String
    }

    // Alert State
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var alertType: AlertType = .info
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("API Configuration")
                .font(.title2)
                .fontWeight(.bold)

            // Two connections, two panes. A segmented picker rather than a TabView, matching
            // ComputerInspectorView — TabView's tab bar collapses to an unreadable pill at this width.
            Picker("Section", selection: $selectedSection) {
                Text("Jamf Pro").tag(0)
                Text("Apple Business Manager").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedSection {
                case 0: jamfTab
                default: appleBusinessManagerTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Footer Buttons
            HStack {
                // Clear All Button
                if !instanceURL.isEmpty || credentials.hasCredentials || credentials.hasABMCredentials {
                    Button(action: clearAllSettings) {
                        Label("Clear All", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove every stored credential, for both Jamf Pro and Apple Business Manager")
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 660)
        .appBackground()
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Jamf Pro tab

    private var jamfTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            // Import/Export Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Import / Export Settings")
                        .font(.headline)
                }
                
                Text("Share your Jamf connection settings with team members using configuration files. Exported files are encrypted with a passphrase you choose — send the passphrase separately from the file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 12) {
                    // Import Button
                    Button(action: importSettings) {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Import settings from a .jamfconfig file")
                    
                    // Export Button (only enabled if settings are filled)
                    Button(action: exportSettings) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(instanceURL.isEmpty || !credentials.hasCredentials)
                    .help("Export current settings to an encrypted .jamfconfig file")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            
            // Manual Configuration Section
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(.secondary)
                    Text("Manual Configuration")
                        .font(.headline)
                }
                
                VStack(alignment: .leading) {
                    Text("Jamf Instance URL")
                        .font(.caption)
                    TextField("https://...", text: $instanceURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading) {
                    Text("Client ID")
                        .font(.caption)
                    TextField("e.g. 34065bc6-...", text: $credentials.clientId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading) {
                    Text("Client Secret")
                        .font(.caption)
                    SecureField("Paste Secret Here", text: $credentials.clientSecret)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                // The credentials are stored in the Keychain. If that ever fails they are held for
                // this session only, so the failure has to be visible rather than silent.
                if let keychainError = credentials.lastError {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(keychainError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Label("Stored securely in your Keychain.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Apple Business Manager tab

    private var appleBusinessManagerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                abmCredentialsSection
                abmScopeSection
                abmTestSection
                abmDataSection
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await fleet.loadFromCache()
        }
    }

    private var abmDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundColor(.secondary)
                Text("Fleet Data")
                    .font(.headline)
            }

            Text("Purchase and warranty data is fetched once and cached for seven days, because Apple Business Manager has no bulk warranty endpoint — every device costs its own request.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: fleet.isStale ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                    .foregroundColor(fleet.isStale ? .orange : .green)
                Text(cacheAgeText)
                    .font(.caption)
                Spacer()
            }

            if fleet.isRefreshing, let progress = fleet.progress {
                VStack(alignment: .leading, spacing: 4) {
                    if progress.total > 0 {
                        ProgressView(value: progress.fraction)
                        Text("\(progress.completed) of \(progress.total) devices")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                        Text("Fetching the device list…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Button(action: refreshABMData) {
                    Label("Refresh Apple Business Manager Data", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(fleet.isRefreshing || !credentials.hasABMCredentials || abmMDMServerId.isEmpty)

                Spacer()
            }

            if let summary = fleet.lastSummary {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(summary.macCount) Mac\(summary.macCount == 1 ? "" : "s") retrieved")
                        .fontWeight(.medium)
                    Text("\(summary.outOfWarranty) out of warranty")
                    if summary.noWarrantyRecord > 0 {
                        Text("\(summary.noWarrantyRecord) with no warranty record")
                    }
                    if summary.warrantyUnavailable > 0 {
                        Text("\(summary.warrantyUnavailable) whose warranty could not be fetched")
                            .foregroundColor(.orange)
                    }
                    Text("\(summary.inferredPurchaseDates) with an inferred purchase date")
                    if summary.missingPurchaseDates > 0 {
                        Text("\(summary.missingPurchaseDates) with no purchase date at all")
                    }
                    if summary.nonMacCount > 0 {
                        Text("\(summary.nonMacCount) assigned device\(summary.nonMacCount == 1 ? "" : "s") skipped as not a Mac")
                    }
                    if summary.failedCount > 0 {
                        Text("\(summary.failedCount) could not be retrieved")
                            .foregroundColor(.orange)
                        if let reason = summary.failureReason {
                            Text(reason)
                                .foregroundColor(.orange)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }

            if let error = fleet.lastError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var cacheAgeText: String {
        guard let refreshedAt = fleet.refreshedAt else {
            return "No data cached yet."
        }
        let relative = Self.relativeFormatter.localizedString(for: refreshedAt, relativeTo: Date())
        return fleet.isStale
            ? "Last refreshed \(relative) — out of date."
            : "Last refreshed \(relative)."
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var abmCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.secondary)
                Text("API Credentials")
                    .font(.headline)
            }

            Text("Optional. Adds purchase date, warranty and lifecycle data to the Computers module. Create an API account in Apple Business Manager under Preferences → API, then enter its details here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading) {
                Text("Client ID")
                    .font(.caption)
                TextField("BUSINESSAPI.6d49c089-...", text: $credentials.abmClientId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading) {
                Text("Key ID")
                    .font(.caption)
                TextField("e.g. 6d49c089-7be5-...", text: $credentials.abmKeyId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Private Key")
                    .font(.caption)

                HStack(spacing: 12) {
                    if credentials.hasABMPrivateKey {
                        Label("Private key imported", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("No private key", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    Button(credentials.hasABMPrivateKey ? "Replace…" : "Import…") {
                        importABMPrivateKey()
                    }
                    .buttonStyle(.bordered)
                    .help("Select the private key file downloaded from Apple Business Manager")

                    if credentials.hasABMPrivateKey {
                        Button("Remove") {
                            credentials.removeABMPrivateKey()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                Text("Apple issues this key once. It is stored in your Keychain, is never shown, and is never written to an exported settings file. Keep your own secure backup, then delete the downloaded copy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var abmScopeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                Text("Scope & Lifecycle")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MDM Server ID")
                    .font(.caption)
                TextField("e.g. C8F02BFBF40C4A53B99E72EA9076EDFE", text: $abmMDMServerId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("Only devices assigned to this MDM server are fetched, so iPhones and iPads are never downloaded. Run Test Connection with this field empty to list the servers in your organisation.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $abmLifecycleYears, in: 1...10) {
                    Text("Lifecycle: purchase date plus \(abmLifecycleYears) year\(abmLifecycleYears == 1 ? "" : "s")")
                        .font(.caption)
                }
                Text("Apple Business Manager does not hold a lifecycle date, so it is calculated from the purchase date.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var abmTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: testABMConnection) {
                    if isTestingABM {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTestingABM || !credentials.hasABMCredentials)

                Spacer()
            }

            if !credentials.hasABMCredentials {
                Text("Enter a Client ID and Key ID and import a private key to enable the test.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let outcome = abmTestResult {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(outcome.isSuccess ? .green : .orange)
                    Text(outcome.message)
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background((outcome.isSuccess ? Color.green : Color.orange).opacity(0.08))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Actions
    
    func importSettings() {
        let result = SettingsService.importSettings()
        
        switch result {
        case .success(let config):
            // Update all settings. The credentials are applied together so a partial import cannot
            // leave a client ID and secret belonging to different instances.
            instanceURL = config.instanceURL
            credentials.apply(clientId: config.clientId, clientSecret: config.clientSecret)

            // Show success message
            alertType = .success
            alertTitle = "Import Successful"
            
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateString = formatter.string(from: config.exportDate)
            
            alertMessage = """
            Configuration imported successfully!
            
            Instance: \(config.instanceURL)
            Exported: \(dateString)
            
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
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret
        )
        
        switch result {
        case .success(let url):
            alertType = .success
            alertTitle = "Export Successful"
            alertMessage = """
            Configuration exported successfully!
            
            File saved to:
            \(url.path)
            
            Share this file with team members to quickly configure their Jamf Commander app. They will need the passphrase you chose — send it to them separately from the file.
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
    
    // MARK: - Apple Business Manager actions

    /// Picks the `.pem`, validates it parses as a P-256 key, and stores it in the Keychain. Rejecting
    /// a wrong file here is the whole point: Apple's token endpoint reports every key problem as a
    /// bare `invalid_client`, long after the mistake was made.
    private func importABMPrivateKey() {
        switch SettingsService.importABMPrivateKeyFile() {
        case .success(let pem):
            do {
                try credentials.importABMPrivateKey(pem: pem)
                abmTestResult = nil

                alertType = .success
                alertTitle = "Private Key Imported"
                alertMessage = """
                The key has been stored in your Keychain.

                Apple issues this key only once. Keep your own secure backup, then delete the downloaded file.
                """
                showAlert = true
            } catch {
                alertType = .error
                alertTitle = "Import Failed"
                alertMessage = error.localizedDescription
                showAlert = true
            }

        case .failure(let error):
            if case .userCancelled = error { return }

            alertType = .error
            alertTitle = "Import Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func testABMConnection() {
        isTestingABM = true
        abmTestResult = nil

        Task {
            do {
                let report = try await ABMAPIService.shared.testConnection(mdmServerId: abmMDMServerId)
                await MainActor.run {
                    abmTestResult = ABMTestOutcome(isSuccess: true, message: abmSuccessMessage(for: report))
                    isTestingABM = false
                }
            } catch {
                await MainActor.run {
                    abmTestResult = ABMTestOutcome(isSuccess: false, message: error.localizedDescription)
                    isTestingABM = false
                }
            }
        }
    }

    /// Reports what the connection actually found. With no MDM server set this lists the servers and
    /// their identifiers, so the field above can be filled in without a trip to the ABM website.
    private func abmSuccessMessage(for report: ABMConnectionReport) -> String {
        if let count = report.assignedDeviceCount {
            let devices = "\(count) device\(count == 1 ? "" : "s") assigned"
            if let name = report.selectedServerName {
                return "Connected to \(name). \(devices)."
            }
            return "Connected. \(devices) to the MDM server ID entered above."
        }

        guard !report.servers.isEmpty else {
            return "Connected, but no MDM servers were found in this organisation."
        }

        let list = report.servers
            .map { "•  \($0.displayName) — \($0.id)" }
            .joined(separator: "\n")

        return """
        Connected. MDM servers in your organisation:

        \(list)

        Copy the identifier of the server Jamf Pro uses into the MDM Server ID field above.
        """
    }

    private func refreshABMData() {
        Task { await fleet.refresh() }
    }

    func clearAllSettings() {
        instanceURL = ""
        abmTestResult = nil
        credentials.clearAll()
        // The cached fleet was fetched with credentials that no longer exist; keeping it would show
        // data the app can no longer refresh or verify.
        Task { await fleet.clear() }

        alertType = .info
        alertTitle = "Settings Cleared"
        alertMessage = "All configuration settings have been cleared."
        showAlert = true
    }
}
