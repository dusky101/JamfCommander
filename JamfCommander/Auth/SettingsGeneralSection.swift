//
//  SettingsGeneralSection.swift
//  JamfCommander
//
//  Created by Marc Oliff on 19/09/2026.
//

import SwiftUI

/// The **General** tab of Settings: how the app behaves, as opposed to how it reaches Jamf.
///
/// Currently one setting. It is a tab of its own because credentials and preferences are different
/// kinds of thing, and mixing them is how a settings sheet becomes a single unreadable column.
struct SettingsGeneralSection: View {
    /// Whether the Installomator sidebar hint may still appear.
    @AppStorage(SidebarHint.installomator.storageKey) private var showInstallomatorHint = true

    var body: some View {
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
}
