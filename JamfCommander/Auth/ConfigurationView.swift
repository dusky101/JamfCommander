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
    /// Named to sit beside **Jamf Pro** rather than alone as "Platform", which said nothing about
    /// which Jamf this is. They are two different systems with two different credentials, and the
    /// commonest setup mistake is assuming the Jamf Pro client works here.
    case jamfPlatform = "Jamf Platform"
    case transfer = "Import & Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .jamfPro: "key.horizontal"
        case .jamfPlatform: "square.stack.3d.up"
        case .transfer: "arrow.up.arrow.down.circle"
        }
    }

    /// The one-line explanation under the title on each page.
    var summary: String {
        switch self {
        case .general: "How the app behaves: where its data comes from, and the guidance it offers."
        case .jamfPro: "An API client created in Jamf Pro. Every module except Blueprints uses it."
        case .jamfPlatform: "A separate integration created in Jamf Account, for Jamf's Platform API Gateway. Only Blueprints needs it, and the Jamf Pro client above will not work here."
        case .transfer: "Move a configuration between Macs as a .jamfconfig file."
        }
    }

    /// Whether this page holds credentials, and so whether "Clear All" belongs beneath it.
    var holdsCredentials: Bool { self != .general }

    /// How to obtain what this page asks for.
    ///
    /// Condensed from the guide rather than written afresh — `Resources/Help/api-client.md`,
    /// `blueprints-integration.md` and `settings-files.md` are the source, and `helpLinks` below
    /// sends the reader to them for the full version. Two copies of a setup procedure drift; a
    /// summary that names the page it came from does not.
    var setupSteps: [String] {
        switch self {
        case .general:
            []
        case .jamfPro:
            [
                "In Jamf Pro, go to Settings → System → API roles and clients.",
                "On API Roles, choose New. Name it, add the privileges this app needs, and save.",
                "On API Clients, choose New. Assign that role, set a token lifetime — 30 minutes is ample — then save and Enable it.",
                "Choose Generate client secret and copy it at once. Jamf shows it only the once.",
                "Copy the Client ID from the same screen, and use your Jamf URL above."
            ]
        case .jamfPlatform:
            [
                "Sign in to Jamf Account — not Jamf Pro — and choose Integrations.",
                "Choose Create integration and give it a name.",
                "Set the scope level to platform environment. An integration scoped to a single tenant cannot reach these APIs, and this is the step that most often goes wrong.",
                "Grant six capabilities: blueprints:read, create, update, delete and deploy, plus device-groups:read.",
                "Create it, then copy the client ID and secret.",
                "Copy the environment ID from the Integration details panel — it is a UUID."
            ]
        case .transfer:
            [
                "Export writes a .jamfconfig file carrying both sets of credentials.",
                "Import merges what the file holds: anything it does not carry is left exactly as it is."
            ]
        }
    }

    /// Pages of the guide worth opening from here, most relevant first.
    var helpLinks: [(title: String, topic: String)] {
        switch self {
        case .general:
            []
        case .jamfPro:
            [("Creating the API client", "api-client"), ("Which privileges to grant", "privileges")]
        case .jamfPlatform:
            [("Creating the Blueprints integration", "blueprints-integration")]
        case .transfer:
            [("Configuration files", "settings-files")]
        }
    }
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

    @Environment(\.openWindow) private var openWindow
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
        VStack(spacing: 0) {
            // The sidebar of a `NavigationSplitView` runs the full height of the window, so the
            // traffic lights float *over* its first row — they hid "General" entirely, and no
            // amount of padding on a header fixed it because the header then collided instead.
            // This reserves the strip they occupy and nothing is drawn in it. The app already
            // solves this twice by hand: `ContentView`'s brand header and the guide's index header
            // both carry a top padding whose only job is this.
            //
            // No "Settings" heading here: the window's own title bar already says it, and a second
            // copy in the rail was one of three the window ended up showing.
            Color.clear
                .frame(height: 30)

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
            .listStyle(.sidebar)
        }
    }

    // MARK: - Detail

    /// Everything in one `ScrollView`, header included.
    ///
    /// Not a `VStack` with a pinned header above a scroll area, which is what this was: the detail
    /// pane also runs under the title bar, and a `VStack` there is drawn beneath the window's title
    /// — so the page heading sat behind the word "Settings". A `ScrollView` is inset for the title
    /// bar automatically, which is why `HelpPage` has looked right since the day the guide was
    /// converted.
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.rawValue)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(page.summary)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !page.setupSteps.isEmpty {
                    setupCard
                }

                switch page {
                case .general:
                    SettingsGeneralSection()
                case .jamfPro:
                    SettingsJamfProSection()
                case .jamfPlatform:
                    SettingsPlatformSection(api: api)
                case .transfer:
                    SettingsTransferSection(onImport: importSettings, onExport: exportSettings)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Only under the pages that hold credentials, and only when there is something to clear.
        // It empties **both** APIs wherever it is pressed — the help text says so, and that is why
        // it is not offered under General, where it would read as clearing what is on screen.
        .safeAreaInset(edge: .bottom) {
            if page.holdsCredentials, hasJamfProSettings || hasPlatformSettings {
                VStack(spacing: 0) {
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
                .background(.ultraThinMaterial)
            }
        }
        // There is no Done button. A window closes the way every other window closes, and "Done"
        // reads as "save" — which these fields do not need, since every one is `@AppStorage` and is
        // stored as it is typed.
    }

    /// How to obtain what this page asks for, and where to read the long version.
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Setting this up", systemImage: "list.number")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(page.setupSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            // So the text of every step starts at the same x.
                            .frame(width: 18, alignment: .trailing)

                        Text(step)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !page.helpLinks.isEmpty {
                Divider()

                // Deep links into the guide rather than the whole procedure repeated here. The
                // guide is the source; this card is the summary, and one of them has screenshots
                // and Jamf's own documentation links.
                HStack(spacing: 12) {
                    ForEach(page.helpLinks, id: \.topic) { link in
                        Button {
                            HelpPresenter.shared.request(link.topic)
                            openWindow(id: HelpWindowID)
                        } label: {
                            Label(link.title, systemImage: "book")
                                .font(.callout)
                        }
                        .buttonStyle(.link)
                    }

                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
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
