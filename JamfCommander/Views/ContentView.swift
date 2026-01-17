//
//  ContentView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

// FIX: A safe wrapper for the sheet so we don't need to extend Int
struct InspectorSelection: Identifiable {
    let id: Int
}

struct ContentView: View {
    @StateObject private var api = JamfAPIService()
    
    // App State
    @State private var isLoggedIn = false
    @State private var isBusy = false
    @State private var showConfigSheet = false
    @State private var statusMessage = "Please initialise connection."
    
    // Data State
    @State private var profiles: [ConfigProfile] = []
    @State private var categories: [Category] = []
    @State private var selectedProfileIDs = Set<ConfigProfile.ID>()
    
    // Inspector State (Updated to use the wrapper)
    @State private var inspectorSelection: InspectorSelection?
    
    var body: some View {
        NavigationSplitView {
            // MARK: - SIDEBAR
            ZStack {
                // Frosted glass background
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Label("Jamf Commander", systemImage: "command.circle.fill")
                            .font(.headline)
                            .imageScale(.large)
                        Spacer()
                        Button(action: { showConfigSheet = true }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                    }
                    .padding(.top)
                    
                    Divider()
                        .opacity(0.5)
                    
                    // Sidebar Content
                    if !isLoggedIn {
                        LoginView(
                            api: api,
                            isLoggedIn: $isLoggedIn,
                            statusMessage: $statusMessage,
                            isBusy: $isBusy,
                            onLoginSuccess: refreshAllData
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        ActionPanelView(
                            api: api,
                            categories: categories,
                            selectedProfileIDs: $selectedProfileIDs,
                            isBusy: $isBusy,
                            statusMessage: $statusMessage,
                            onRefresh: refreshAllData
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Status Footer
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusColor.opacity(0.5), radius: 4)
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.bottom)
                }
                .padding(.horizontal)
            }
            .liquidGlass(.sidebar) // Apply styling
            .frame(minWidth: 260)
            
        } detail: {
            // MARK: - MAIN CONTENT
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoggedIn {
                    ProfileTableView(
                        profiles: profiles,
                        categories: categories,
                        selectedProfileIDs: $selectedProfileIDs
                    )
                    // Context Menu
                    .contextMenu(forSelectionType: ConfigProfile.ID.self) { selectedIDs in
                        if selectedIDs.count == 1, let id = selectedIDs.first {
                            Button {
                                // FIX: Use the wrapper struct
                                inspectorSelection = InspectorSelection(id: id)
                            } label: {
                                Label("Inspect Profile Source", systemImage: "doc.text.magnifyingglass")
                            }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Jamf Commander", systemImage: "lock.shield")
                    } description: {
                        Text("Please sign in securely to manage your fleet.")
                    }
                }
            }
            .liquidGlass(.content)
        }
        // Configuration Sheet
        .sheet(isPresented: $showConfigSheet) {
            ConfigurationView()
        }
        // Inspector Sheet (FIX: Uses the wrapper)
        .sheet(item: $inspectorSelection) { selection in
            ProfileDetailView(profileId: selection.id, api: api)
        }
        // Animations
        .animation(.default, value: isLoggedIn)
    }
}

// MARK: - Logic Extension

extension ContentView {
    var statusColor: Color {
        if isBusy { return .blue }
        if statusMessage.lowercased().contains("failed") || statusMessage.lowercased().contains("error") { return .red }
        if !isLoggedIn { return .gray }
        return .green
    }
    
    func refreshAllData() async {
        do {
            async let fetchedProfiles = api.fetchProfiles()
            async let fetchedCategories = api.fetchCategories()
            
            let (p, c) = try await (fetchedProfiles, fetchedCategories)
            
            await MainActor.run {
                self.profiles = p.sorted { $0.name < $1.name }
                self.categories = c.sorted { $0.name < $1.name }
                self.statusMessage = "Ready."
            }
        } catch {
            await MainActor.run {
                statusMessage = "Failed to refresh data."
            }
        }
    }
}

#Preview {
    ContentView()
}
