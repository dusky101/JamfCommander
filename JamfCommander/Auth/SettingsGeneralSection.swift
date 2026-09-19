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
    /// How many sidebar hints are currently switched off.
    ///
    /// Read once when Settings opens rather than held as `@AppStorage`: the keys are owned by
    /// `SidebarHint` and there is one per hint, so binding to them individually would mean editing
    /// this view every time a hint is added. Settings is modal, so nothing can dismiss a hint while
    /// this is on screen.
    @State private var suppressedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Guidance", systemImage: "questionmark.bubble")
                .font(.headline)

            Text("Some modules explain themselves the first time you hover over them. Once dismissed they stay dismissed — bring them all back here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Module explanations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Show All Again") {
                    SidebarHint.restoreAll()
                    suppressedCount = 0
                }
                .disabled(suppressedCount == 0)
                .help("Bring back every explanation that appears when you hover over a module")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .onAppear { suppressedCount = SidebarHint.suppressed.count }
    }

    private var statusDescription: String {
        switch suppressedCount {
        case 0: return "All shown on hover"
        case 1: return "1 dismissed"
        default: return "\(suppressedCount) dismissed"
        }
    }
}
