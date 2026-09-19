//
//  SettingsJamfProSection.swift
//  JamfCommander
//
//  Created by Marc Oliff on 19/09/2026.
//

import SwiftUI

/// The Jamf Pro API credentials: the client every module except Blueprints uses.
///
/// There is deliberately no default instance URL. An app that deletes things should not arrive
/// pointing at somebody else's production tenant, so the field starts empty and carries an example
/// as its placeholder.
struct SettingsJamfProSection: View {
    @AppStorage("jamfInstanceURL") private var instanceURL = ""
    @AppStorage("clientId") private var clientId = ""
    @AppStorage("clientSecret") private var clientSecret = ""

    var body: some View {
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
                TextField("https://yourcompany.jamfcloud.com", text: $instanceURL)
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
}
