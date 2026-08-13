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

    @Environment(\.dismiss) var dismiss
    
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
        VStack(alignment: .leading, spacing: 20) {
            // Header
            Text("API Configuration")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
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
            
            Spacer()
            
            // Footer Buttons
            HStack {
                // Clear All Button
                if !instanceURL.isEmpty || !credentials.clientId.isEmpty || !credentials.clientSecret.isEmpty {
                    Button(action: clearAllSettings) {
                        Label("Clear All", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
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
        .frame(width: 500, height: 600)
        .appBackground()
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
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
    
    func clearAllSettings() {
        instanceURL = ""
        credentials.clearAll()

        alertType = .info
        alertTitle = "Settings Cleared"
        alertMessage = "All configuration settings have been cleared."
        showAlert = true
    }
}
