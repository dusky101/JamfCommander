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
    @State private var currentModule: AppModule = .profiles
    
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
    @AppStorage("jamfInstanceURL") private var storedURL = ""
    @AppStorage("clientId") private var storedClientId = ""
    @AppStorage("clientSecret") private var storedClientSecret = ""
    
    var body: some View {
        NavigationSplitView {
            // MARK: - SIDEBAR
            ZStack {
                Color.clear.background(.ultraThinMaterial).ignoresSafeArea()
                
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
            }
            .frame(minWidth: 220)
            
        } detail: {
            // MARK: - MAIN CONTENT
            ZStack {
                // Main Background
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if !isLoggedIn {
                    LoginView(
                        api: api,
                        isLoggedIn: $isLoggedIn,
                        statusMessage: $statusMessage,
                        isBusy: $isBusy,
                        onLoginSuccess: refreshAllData
                    )
                    .frame(maxWidth: 400)
                } else {
                    // Module Switcher
                    switch currentModule {
                    case .dashboard:
                        Text("Dashboard Coming Soon").font(.largeTitle).foregroundColor(.secondary)
                        
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
                        
                    case .policies:
                        PoliciesDashboardView(api: api) // <--- UPDATED
                        
                    case .scripts:
                        ScriptsDashboardView(api: api)
                    }
                }
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            ConfigurationView()
        }
        // MARK: - AUTO LOGIN TRIGGER
        .task {
            // Check if we have saved credentials
            if !isLoggedIn && !storedURL.isEmpty && !storedClientId.isEmpty && !storedClientSecret.isEmpty {
                await performAutoLogin()
            }
        }
    }
    
    // MARK: - Functions
    
    func performAutoLogin() async {
        isBusy = true
        statusMessage = "Auto-connecting..."
        
        do {
            // Attempt to authenticate using stored credentials
            try await api.authenticate(
                url: storedURL,
                clientId: storedClientId,
                clientSecret: storedClientSecret
            )
            
            // If successful, refresh data (for profiles)
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
