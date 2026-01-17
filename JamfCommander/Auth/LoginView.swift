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
                Text("⚠️ Credentials missing")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Please open Settings (Gear Icon) to configure your Client ID and Secret.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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