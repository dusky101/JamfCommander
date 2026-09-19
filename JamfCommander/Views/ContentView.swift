//
//  ContentView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var api = JamfAPIService()
    
    // Navigation State
    //
    // The direction travels with the selection rather than being worked out afterwards. An
    // `onChange` would fire after the pane had already been rebuilt, so the new pane would animate
    // using the *previous* move's direction \u2014 always one click behind.
    private struct ModuleSelection: Equatable {
        var module: AppModule
        var direction: ModuleTransitionDirection = .forward

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.module == rhs.module }
    }

    @State private var selection = ModuleSelection(module: .dashboard)

    /// What every child still sees: a plain `Binding<AppModule>`. Setting it works out which way
    /// through the sidebar the move went, so the sidebar and the dashboard tiles need to know
    /// nothing about transitions.
    private var currentModule: Binding<AppModule> {
        Binding(
            get: { selection.module },
            set: { newModule in
                guard newModule != selection.module else { return }
                selection = ModuleSelection(
                    module: newModule,
                    direction: newModule.navigationIndex >= selection.module.navigationIndex
                        ? .forward
                        : .backward
                )
            }
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // App State
    @State private var isLoggedIn = false
    @State private var isBusy = false
    @ObservedObject private var settingsPresenter = SettingsPresenter.shared
    @State private var statusMessage = "Please initialise connection."
    
    // Data (For Profile Dashboard Only - Old Pattern)
    @State private var profiles: [ConfigProfile] = []
    @State private var categories: [Category] = []
    @State private var selectedProfileIDs = Set<ConfigProfile.ID>()
    
    // MARK: - Auto-Login Storage
    @AppStorage("jamfInstanceURL") private var storedURL = ""
    @AppStorage("clientId") private var storedClientId = ""
    @AppStorage("clientSecret") private var storedClientSecret = ""

    private var hasStoredCredentials: Bool {
        !storedURL.isEmpty && !storedClientId.isEmpty && !storedClientSecret.isEmpty
    }

    /// Whether the first module has finished fetching. Set once, by the Dashboard.
    @State private var hasCompletedInitialLoad = false

    /// The app is not ready to be used yet — either the saved session is still being restored, or it
    /// has been and the Dashboard is still fetching. Only ever true when there is a connection to
    /// wait on; somebody who has not connected yet should meet the login screen, not a curtain.
    private var isPreparing: Bool {
        guard hasStoredCredentials else { return false }
        if isBusy && !isLoggedIn { return true }
        return isLoggedIn && !hasCompletedInitialLoad
    }
    
    var body: some View {
        NavigationSplitView {
            // MARK: - SIDEBAR
            VStack(spacing: 0) {
                // Brand Header
                HStack {
                    Image(systemName: "command.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Commander")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                // Top padding prevents traffic lights from overlapping content
                .padding(.top, 10)
                
                if isLoggedIn {
                    SidebarView(currentModule: currentModule)
                } else {
                    Spacer()
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 8)
                        Text("Restoring session...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Please Initialise.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // Connection Status Footer
                HStack {
                    Circle()
                        .fill(isLoggedIn ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(statusMessage)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.05))
            }
            // 250, not 220. A sidebar row spends 104pt on padding, its icon and the two HStack
            // gaps, so 220 left 116pt for the subtitle — and "Audit what nothing uses" measures
            // 119.1pt at caption2, missing by 1.3pt while Installomator's 114.7pt fitted. 250
            // gives 146pt. Narrower than this the subtitle wraps rather than truncating.
            .frame(minWidth: 250, maxHeight: .infinity)
            // FIX: Apply background logic here to fix the "glitch" without squashing content
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
            
        } detail: {
            // MARK: - MAIN CONTENT
            //
            // The gradient is a `.background`, not a `ZStack` sibling. As a sibling it took part in
            // sizing the pane, and — because a ZStack centres its children — any module whose content
            // measured taller than the pane had its overflow split evenly top and bottom, so the top
            // of it disappeared under the title bar. As a background it is pure decoration: it can
            // ignore the safe area freely without influencing where the module is placed.
            Group {
                if !isLoggedIn {
                    LoginView(
                        api: api,
                        isLoggedIn: $isLoggedIn,
                        statusMessage: $statusMessage,
                        isBusy: $isBusy,
                        onLoginSuccess: { await refreshAllData() }
                    )
                    .frame(maxWidth: 400)
                    // The login form stays centred; only the modules pin to the top.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    moduleContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        // Switching module swaps one branch of a `switch` for another, which SwiftUI
                        // will not always read as an insertion. The id makes the swap explicit so the
                        // transition actually runs, and costs nothing: the branches are distinct
                        // views whose state is discarded on a switch either way.
                        .id(selection.module)
                        .transition(.modulePane(selection.direction))
                        // The pane slides its whole width, so it must not paint outside the detail
                        // area on the way past.
                        .clipped()
                }
            }
            .background {
                AppBackground()
                    .ignoresSafeArea()
            }
            // Long enough to read as a movement, short enough to stay out of the way of somebody
            // going quickly down the sidebar.
            .animation(reduceMotion ? nil : .smooth(duration: 0.34), value: selection.module)
        }
        // Covers both columns until the app can actually answer. Leaving a module mid-fetch cancels
        // every request it had in flight, so somebody clicking through the sidebar during the first
        // load throws away a scan of the whole tenant and starts another.
        .overlay {
            if isPreparing {
                PreparingOverlay(instanceURL: storedURL)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPreparing)
        .sheet(isPresented: $settingsPresenter.isPresented) {
            ConfigurationView(api: api)
        }
        // MARK: - AUTO LOGIN TRIGGER
        .task {
            if !isLoggedIn && !storedURL.isEmpty && !storedClientId.isEmpty && !storedClientSecret.isEmpty {
                await performAutoLogin()
            }
        }
    }
    
    /// The module for the current sidebar selection.
    @ViewBuilder
    private var moduleContent: some View {
        switch selection.module {
        case .dashboard:
            DashboardView(
                api: api,
                currentModule: currentModule,
                onInitialLoadFinished: { hasCompletedInitialLoad = true }
            )

        case .policies:
            PoliciesDashboardView(api: api)

        case .profiles:
            ProfileDashboardView(
                profiles: profiles,
                categories: categories,
                api: api,
                selectedProfileIDs: $selectedProfileIDs,
                refreshAction: refreshAllData
            )

        case .blueprints:
            BlueprintsDashboardView(api: api, showConfigSheet: $settingsPresenter.isPresented)

        case .computers:
            ComputersDashboardView(api: api)

        case .scripts:
            ScriptsDashboardView(api: api)

        case .installomator:
            PackagesDashboardView(api: api)

        case .packages:
            AddPackageView(api: api)

        case .redundant:
            RedundantDashboardView(api: api)
        }
    }

    // MARK: - Functions

    func performAutoLogin() async {
        isBusy = true
        statusMessage = "Auto-connecting..."
        
        do {
            try await api.authenticate(
                url: storedURL,
                clientId: storedClientId,
                clientSecret: storedClientSecret
            )
            await refreshAllData()
            await MainActor.run {
                self.isLoggedIn = true
                self.isBusy = false
                self.statusMessage = "Ready."
            }
        } catch {
            print("Auto-login failed: \(error)")
            await MainActor.run {
                self.statusMessage = "Auto-login failed. Please verify settings."
                self.isBusy = false
            }
        }
    }
    
    /// - Parameter bypassingCache: `true` reads from Jamf regardless of what this session already
    ///   holds. Passed by the Profiles module's Refresh button; left `false` after a write, which
    ///   has already invalidated the cache on its own.
    func refreshAllData(bypassingCache: Bool = false) async {
        do {
            async let fetchedProfiles = api.fetchProfiles(bypassingCache: bypassingCache)
            async let fetchedCategories = api.fetchCategories(bypassingCache: bypassingCache)
            
            let (p, c) = try await (fetchedProfiles, fetchedCategories)
            
            await MainActor.run {
                self.profiles = p.sorted { $0.name < $1.name }
                self.categories = c.sorted { $0.name < $1.name }
                self.statusMessage = "Connected to \(categories.count) categories."
            }
        } catch {
            await MainActor.run {
                statusMessage = "Failed to refresh data."
            }
        }
    }
}

/// What the window shows until the app has its data.
///
/// A modal card over a dimmed app, not a spinner in the detail pane: the sidebar has to be
/// unreachable, and it has to be obvious *why*. It names the instance being read, because somebody
/// with more than one tenant configured needs to know which one they are waiting on.
private struct PreparingOverlay: View {
    let instanceURL: String

    @State private var animateIcon = false

    /// Tidied for display only — a trailing slash is stored but reads as a typo on screen.
    private var instanceDisplay: String {
        let trimmed = instanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 46))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeating, value: animateIcon)

                Text("Please wait until the data is fetched to display the Dashboard for")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(instanceDisplay)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 220)

                Text("Reading every policy takes a moment on a large instance.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(32)
            .frame(width: 420)
            .appBarBackground(cornerRadius: 18)
        }
        // Swallows every click underneath, which is the point.
        .contentShape(Rectangle())
        .onAppear { animateIcon = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Please wait. Fetching data from \(instanceDisplay) to display the Dashboard.")
    }
}
