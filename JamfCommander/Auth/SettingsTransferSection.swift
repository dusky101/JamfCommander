//
//  SettingsTransferSection.swift
//  JamfCommander
//
//  Created by Marc Oliff on 19/09/2026.
//

import SwiftUI

/// The import/export card at the top of the **Jamf Connections** tab.
///
/// Only the buttons and their enablement live here. What a transfer means is
/// `SettingsTransfer`, and the outcome alert belongs to the Settings sheet, so both actions are
/// handed in rather than run from this view.
struct SettingsTransferSection: View {
    var onImport: () -> Void
    var onExport: () -> Void

    // Read directly rather than passed in, matching every other reader of these keys. Used only to
    // decide whether there is anything worth exporting.
    @AppStorage("jamfInstanceURL") private var instanceURL = ""
    @AppStorage("clientId") private var clientId = ""
    @AppStorage("clientSecret") private var clientSecret = ""

    /// A file with no Jamf Pro credentials in it would configure nobody, so exporting is offered
    /// only once all three are present.
    private var canExport: Bool {
        !instanceURL.isEmpty && !clientId.isEmpty && !clientSecret.isEmpty
    }

    var body: some View {
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
                Button(action: onImport) {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Import settings from a .jamfconfig file")

                Button(action: onExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canExport)
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
}
