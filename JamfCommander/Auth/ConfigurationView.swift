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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("API Configuration")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 15) {
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
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }
}
