//
//  LoginView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//


import SwiftUI

struct LoginView: View {
    @ObservedObject var api: JamfAPIService
    
    // Binding allows us to tell the parent (ContentView) when we are done
    @Binding var isLoggedIn: Bool
    @Binding var statusMessage: String
    @Binding var isBusy: Bool
    @Binding var showConfigSheet: Bool // NEW: Allow opening settings
    
    // Local Access to settings
    @AppStorage("jamfInstanceURL") private var savedInstanceURL = "https://zellis.jamfcloud.com"
    @AppStorage("clientId") private var savedClientId = ""
    @AppStorage("clientSecret") private var savedClientSecret = ""
    
    var onLoginSuccess: () async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Connect to Jamf")
                .font(.headline)
            
            if savedClientId.isEmpty || savedClientSecret.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Credentials Missing")
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    
                    Text("You need to configure your Jamf instance URL, Client ID, and Client Secret before you can connect.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Button(action: { showConfigSheet = true }) {
                        Label("Open Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            } else {
                Text("Instance: \(savedInstanceURL)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: performLogin) {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Initialise Connection")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                
                // Add a subtle settings link for users who want to change settings
                Button(action: { showConfigSheet = true }) {
                    Label("Edit Settings", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
    
    func performLogin() {
        isBusy = true
        statusMessage = "Authenticating..."
        
        Task {
            do {
                try await api.authenticate(url: savedInstanceURL, clientId: savedClientId, clientSecret: savedClientSecret)
                
                await onLoginSuccess()
                
                isLoggedIn = true
                isBusy = false
                statusMessage = "Ready."
            } catch {
                isBusy = false
                statusMessage = "Connection failed. Check Client ID/Secret."
            }
        }
    }
}