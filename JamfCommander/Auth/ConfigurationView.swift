//
//  ConfigurationView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//


import SwiftUI
import Combine

/// Carries a request into the Settings window.
///
/// The window itself is opened with `openWindow(id: SettingsWindowID)`; this only says *which page*
/// it should land on. It used to own an `isPresented` flag, which made the existence of Settings a
/// piece of state some view held — a sheet's shape, not a window's. `HelpPresenter` made the same
/// move on 19 September 2026 and is the worked example.
///
/// Shared rather than local because Settings is reachable from places that know nothing about each
/// other: the sidebar footer, the login screen, the Blueprints module, and the standard Settings
/// item in the application menu (⌘,), which lives in the `App` scene.
@MainActor
final class SettingsPresenter: ObservableObject {
    static let shared = SettingsPresenter()
    private init() {}

    /// The page to open on. `nil` opens wherever the reader last was.
    ///
    /// Somebody who has just pressed a button about connecting to Jamf should land on those
    /// credentials, not on application preferences.
    @Published var requestedPage: SettingsPage?

    /// Ask Settings to open on a particular page. **The caller opens the window.**
    func request(_ page: SettingsPage) {
        requestedPage = page
    }
}

/// The pages of Settings, one per section file.
///
/// Four, where the sheet had two tabs and stacked three sections under the second. As a rail each
/// section is reachable in one click, and "Open Settings" from the login screen and from Blueprints
/// can land on the credentials each of them actually means.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case jamfPro = "Jamf Pro"
    case platform = "Platform"
    case transfer = "Import & Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .jamfPro: "key.horizontal"
        case .platform: "square.stack.3d.up"
        case .transfer: "arrow.up.arrow.down.circle"
        }
    }

    /// The one-line explanation under the title on each page.
    var summary: String {
        switch self {
        case .general: "How the app behaves: where its data comes from, and the guidance it offers."
        case .jamfPro: "The Jamf Pro API client this app authenticates with."
        case .platform: "The Jamf Platform API Gateway credentials that Blueprints needs. Created in Jamf Account, not in Jamf Pro."
        case .transfer: "Move a configuration between Macs as a .jamfconfig file."
        }
    }

    /// Whether this page holds credentials, and so whether "Clear All" belongs beneath it.
    var holdsCredentials: Bool { self != .general }
}

struct ConfigurationView: View {
    /// Passed straight through to `SettingsPlatformSection` for its "Test Connection" button, which
    /// is the only part of Settings that calls Jamf. Every credential field is plain `@AppStorage`.
    @ObservedObject var api: JamfAPIService

    // MARK: Jamf Pro API (Classic + Pro endpoints)
    @AppStorage("jamfInstanceURL") private var instanceURL = ""
    @AppStorage("clientId") private var clientId = ""
    @AppStorage("clientSecret") private var clientSecret = ""

    // MARK: Platform API Gateway (blueprints)
    @AppStorage(PlatformCredentialsStore.regionKey) private var platformRegion = PlatformRegion.eu.rawValue
    @AppStorage(PlatformCredentialsStore.environmentIdKey) private var platformEnvironmentId = ""
    @AppStorage(PlatformCredentialsStore.clientIdKey) private var platformClientId = ""
    @AppStorage(PlatformCredentialsStore.clientSecretKey) private var platformClientSecret = ""

    @ObservedObject private var presenter = SettingsPresenter.shared
    /// The page on screen. Survives the window being closed and reopened, which is the point of a
    /// window: you come back to where you were, unless a caller asked for somewhere specific.
    @State private var page: SettingsPage = .general

    // Alert State
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var hasJamfProSettings: Bool {
        !instanceURL.isEmpty || !clientId.isEmpty || !clientSecret.isEmpty
    }

    private var hasPlatformSettings: Bool {
        !platformEnvironmentId.isEmpty || !platformClientId.isEmpty || !platformClientSecret.isEmpty
    }

    var body: some View {
        NavigationSplitView {
            rail
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        // A floor, not a target — the scene's `.defaultSize` decides how it opens and the reader
        // decides after that. Below this the rail and a credential field stop fitting side by side:
        // the Platform page's longest field label and its text field need the detail pane, and the
        // rail's own minimum is 200.
        .frame(minWidth: 720, minHeight: 560)
        .appBackground()
        .onAppear { applyRequestedPage() }
        .onChange(of: presenter.requestedPage) { applyRequestedPage() }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    /// Honours a caller that asked for a particular page, then clears the request.
    ///
    /// Cleared so that reopening the window later lands where the reader left off rather than
    /// repeating the last deep link — the request is an instruction, not a preference.
    private func applyRequestedPage() {
        guard let requested = presenter.requestedPage else { return }
        page = requested
        presenter.requestedPage = nil
    }

    // MARK: - Rail

    private var rail: some View {
        List(SettingsPage.allCases, selection: Binding(
            get: { page },
            // A rail selection is never empty: clicking the selected row again would otherwise
            // deselect it and leave the detail pane blank.
            set: { if let new = $0 { page = new } }
        )) { option in
            Label(option.rawValue, systemImage: option.icon)
                .tag(option)
                .help(option.summary)
        }
        .navigationTitle("Settings")
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(page.rawValue)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(page.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch page {
                    case .general:
                        SettingsGeneralSection()
                    case .jamfPro:
                        SettingsJamfProSection()
                    case .platform:
                        SettingsPlatformSection(api: api)
                    case .transfer:
                        SettingsTransferSection(onImport: importSettings, onExport: exportSettings)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Only under the pages that hold credentials, and only when there is something to
            // clear. It empties **both** APIs wherever it is pressed — the help text says so, and
            // that is why it is not offered under General, where it would read as clearing the
            // preferences on screen.
            if page.holdsCredentials, hasJamfProSettings || hasPlatformSettings {
                Divider()

                HStack {
                    Button(action: clearAllSettings) {
                        Label("Clear All", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove every stored credential, for both APIs")

                    Spacer()
                }
                .padding()
            }
        }
        // There is no Done button. A window is closed the way every other window is closed, and a
        // Done button inside one reads as "save", which these fields do not need — every one of
        // them is `@AppStorage` and is already stored as it is typed.
    }

    // MARK: - Actions

    /// The credentials exactly as Settings currently holds them.
    private var storedCredentials: JamfCredentials {
        JamfCredentials(
            instanceURL: instanceURL,
            clientId: clientId,
            clientSecret: clientSecret,
            platformRegion: platformRegion,
            platformEnvironmentId: platformEnvironmentId,
            platformClientId: platformClientId,
            platformClientSecret: platformClientSecret
        )
    }

    private func store(_ credentials: JamfCredentials) {
        instanceURL = credentials.instanceURL
        clientId = credentials.clientId
        clientSecret = credentials.clientSecret
        platformRegion = credentials.platformRegion
        platformEnvironmentId = credentials.platformEnvironmentId
        platformClientId = credentials.platformClientId
        platformClientSecret = credentials.platformClientSecret
    }

    func importSettings() {
        switch SettingsTransfer.importConfiguration(mergingInto: storedCredentials) {
        case .imported(let credentials, let outcome):
            // Storing the credentials is enough to clear a stale Platform test result: the section
            // watches those values. A file carrying no Platform values changes nothing there, and
            // a result obtained for the integration still in place stays valid.
            store(credentials)

            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true

        case .cancelled:
            return // Dismissing the open panel is not a failure.

        case .failed(let outcome):
            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true
        }
    }

    func exportSettings() {
        switch SettingsTransfer.exportConfiguration(storedCredentials) {
        case .exported(let outcome):
            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true

        case .cancelled:
            return // Dismissing the save panel is not a failure.

        case .failed(let outcome):
            alertTitle = outcome.title
            alertMessage = outcome.message
            showAlert = true
        }
    }

    func clearAllSettings() {
        instanceURL = ""
        clientId = ""
        clientSecret = ""

        platformEnvironmentId = ""
        platformClientId = ""
        platformClientSecret = ""
        platformRegion = PlatformRegion.eu.rawValue
        // Emptying the Platform fields clears any test result on its own — the section watches them.

        alertTitle = "Settings Cleared"
        alertMessage = "All configuration settings have been cleared."
        showAlert = true
    }
}
