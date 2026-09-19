//
//  SettingsGeneralSection.swift
//  JamfCommander
//
//  Created by Marc Oliff on 19/09/2026.
//

import SwiftUI

/// The **General** tab of Settings: how the app behaves, as opposed to how it reaches Jamf.
///
/// A tab of its own because credentials and preferences are different kinds of thing, and mixing
/// them is how a settings sheet becomes a single unreadable column.
struct SettingsGeneralSection: View {
    /// **Live** or **Cached** — see `SessionCache`. Cached by default: reading the whole tenant
    /// again every time a module is opened is the app's single largest source of waiting, and
    /// anyone who would rather pay that cost for certainty can say so here.
    @AppStorage(SessionCache.cachingEnabledKey) private var isCaching = true

    /// When the cache last had something read into it, so this tab can say whether it holds
    /// anything at all rather than offering a button that might do nothing visible.
    @ObservedObject private var cache = SessionCache.shared

    /// How many sidebar hints are currently switched off.
    ///
    /// Read once when Settings opens rather than held as `@AppStorage`: the keys are owned by
    /// `SidebarHint` and there is one per hint, so binding to them individually would mean editing
    /// this view every time a hint is added. Settings is modal, so nothing can dismiss a hint while
    /// this is on screen.
    @State private var suppressedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dataSection
            guidanceSection
        }
    }

    // MARK: - Data

    /// How the app gets its data when you move between modules.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.headline)

            Text("Reading a whole Jamf instance takes a while, and most modules read the same things. Cached reads each once and reuses it until something changes; Live reads again every time you open a module.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data source")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(modeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Picker("Data source", selection: $isCaching) {
                        Text("Live").tag(false)
                        Text("Cached").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: isCaching) { _, nowCaching in
                        // Turning caching off must also throw away what is already held. Leaving it
                        // in memory would mean choosing Live and still having the tenant's records
                        // sitting there — and served again the moment the switch went back.
                        if !nowCaching { SessionCache.shared.invalidateAll() }
                    }
                }

                // Only meaningful in Cached mode: in Live mode every read already goes to Jamf.
                if isCaching {
                    Divider()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Held data")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(heldDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Refresh Data") {
                            // The same signal every write sends: discard everything and ask any
                            // module currently on screen to reload.
                            RefreshCoordinator.shared.requestRefresh()
                        }
                        .disabled(cache.readAt.isEmpty)
                        .help("Discard everything read so far. The next time a module loads, it reads from Jamf again.")
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    private var modeDescription: String {
        isCaching
            ? "Read once, then reused until something is added, deleted, updated or moved — or until you refresh."
            : "Every module reads from Jamf each time you open it."
    }

    private var heldDescription: String {
        switch cache.readAt.count {
        case 0: return "Nothing held yet"
        case 1: return "1 kind of data held"
        default: return "\(cache.readAt.count) kinds of data held"
        }
    }

    // MARK: - Guidance

    private var guidanceSection: some View {
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
