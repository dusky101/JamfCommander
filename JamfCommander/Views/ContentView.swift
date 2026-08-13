//
//  ContentView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var api = JamfAPIService()
    @ObservedObject private var helpPresenter = HelpPresenter.shared
    
    // Navigation State
    @State private var currentModule: AppModule = .dashboard
    
    // App State
    @State private var isLoggedIn = false
    @State private var isBusy = false
    @State private var showConfigSheet = false
    @State private var statusMessage = "Please initialise connection."
    
    // Data (For Profile Dashboard Only - Old Pattern)
    @State private var profiles: [ConfigProfile] = []
    @State private var categories: [Category] = []
    @State private var selectedProfileIDs = Set<ConfigProfile.ID>()
    
    // MARK: - Auto-Login Storage
    // The instance URL is a non-secret endpoint and stays in UserDefaults; the credentials come from
    // the Keychain via CredentialStore.
    @AppStorage("jamfInstanceURL") private var storedURL = ""
    @ObservedObject private var credentials = CredentialStore.shared
    
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
                    SidebarView(currentModule: $currentModule, showConfigSheet: $showConfigSheet)
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
            .frame(minWidth: 220, maxHeight: .infinity)
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
                        showConfigSheet: $showConfigSheet,
                        onLoginSuccess: refreshAllData
                    )
                    .frame(maxWidth: 400)
                    // The login form stays centred; only the modules pin to the top.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    moduleContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .background {
                AppBackground()
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            ConfigurationView()
        }
        // Help is reachable from the sidebar footer and the macOS Help menu, so the presenter is
        // shared rather than local state.
        .sheet(isPresented: $helpPresenter.isPresented) {
            HelpView(onDismiss: { helpPresenter.isPresented = false })
        }
        // MARK: - AUTO LOGIN TRIGGER
        .task {
            if !isLoggedIn && !storedURL.isEmpty && credentials.hasCredentials {
                await performAutoLogin()
            }
        }
    }
    
    /// The module for the current sidebar selection.
    @ViewBuilder
    private var moduleContent: some View {
        switch currentModule {
        case .dashboard:
            DashboardView(api: api, currentModule: $currentModule)

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

        case .computers:
            ComputersDashboardView(api: api)

        case .scripts:
            ScriptsDashboardView(api: api)

        case .packages:
            PackagesDashboardView(api: api)
        }
    }

    // MARK: - Functions

    func performAutoLogin() async {
        isBusy = true
        statusMessage = "Auto-connecting..."
        
        do {
            try await api.authenticate(
                url: storedURL,
                clientId: credentials.clientId,
                clientSecret: credentials.clientSecret
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
    
    func refreshAllData() async {
        do {
            async let fetchedProfiles = api.fetchProfiles()
            async let fetchedCategories = api.fetchCategories()
            
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
