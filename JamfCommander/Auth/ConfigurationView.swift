//
//  ConfigurationView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//


import SwiftUI

struct ConfigurationView: View {
    @AppStorage("jamfInstanceURL") private var instanceURL = "https://zellis.jamfcloud.com"
    @AppStorage("clientId") private var clientId = ""
    @AppStorage("clientSecret") private var clientSecret = ""
    
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
                
                Text("Share your Jamf connection settings with team members using configuration files.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
                    TextField("e.g. 34065bc6-...", text: $clientId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading) {
                    Text("Client Secret")
                        .font(.caption)
                    SecureField("Paste Secret Here", text: $clientSecret)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
            
            // Footer Buttons
            HStack {
                // Clear All Button
                if !instanceURL.isEmpty || !clientId.isEmpty || !clientSecret.isEmpty {
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
            // Update all settings
            instanceURL = config.instanceURL
            clientId = config.clientId
            clientSecret = config.clientSecret
            
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
            clientId: clientId,
            clientSecret: clientSecret
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
        
        alertType = .info
        alertTitle = "Settings Cleared"
        alertMessage = "All configuration settings have been cleared."
        showAlert = true
    }
}
