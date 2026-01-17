//
//  ComputerInspectorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ComputerInspectorView: View {
    let computerId: Int
    @ObservedObject var api: JamfAPIService
    @Environment(\.dismiss) var dismiss
    
    // Use the Pro API Record Model
    @State private var detail: ComputerInventoryRecord?
    @State private var isLoading = true
    
    // View State
    @State private var selectedTab = 0 // 0 = Info, 1 = Profiles
    @State private var profileSearch = ""
    
    // For Inspecting a Profile from the List
    @State private var profileToInspect: InspectorSelection?
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            VStack(spacing: 12) {
                // Top Bar
                ZStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("DEVICE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Text("#\(computerId)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    Text(detail?.general?.name ?? "Loading...")
                        .font(.headline)
                    
                    HStack {
                        Spacer()
                        Button("Close") { dismiss() }.buttonStyle(.bordered)
                    }
                }
                
                // Segmented Picker
                Picker("View", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Profiles").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .disabled(isLoading)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- CONTENT ---
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if let detail = detail {
                if selectedTab == 0 {
                    // INFO TAB
                    ScrollView {
                        VStack(spacing: 20) {
                            // Hardware
                            InfoSection(title: "Hardware", icon: "cpu") {
                                if let hardware = detail.hardware {
                                    InfoRow(label: "Model", value: hardware.model ?? "Unknown")
                                    InfoRow(label: "Processor", value: hardware.processorType ?? "Unknown")
                                    InfoRow(label: "Memory", value: "\(hardware.totalRamMegabytes ?? 0) MB")
                                    InfoRow(label: "Serial", value: hardware.serialNumber ?? "N/A")
                                } else {
                                    Text("No hardware details.")
                                }
                            }
                            
                            // OS & Security
                            InfoSection(title: "OS & Security", icon: "lock.shield") {
                                if let os = detail.operatingSystem {
                                    InfoRow(label: "OS Version", value: "\(os.name ?? "macOS") \(os.version ?? "")")
                                    InfoRow(label: "Build", value: os.build ?? "Unknown")
                                    InfoRow(label: "FileVault", value: os.fileVault2Status ?? "Unknown")
                                }
                            }
                            
                            // Network & Management
                            InfoSection(title: "Status", icon: "antenna.radiowaves.left.and.right") {
                                if let general = detail.general {
                                    InfoRow(label: "IP Address", value: general.lastReportedIp ?? "Unknown")
                                    InfoRow(label: "Last Contact", value: general.lastContactTime ?? "Never")
                                    
                                    let isManaged = general.remoteManagement?.managed ?? false
                                    InfoRow(label: "Managed", value: isManaged ? "Yes" : "No")
                                    
                                    if let user = general.remoteManagement?.managementUsername {
                                        InfoRow(label: "Mgmt Account", value: user)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    // PROFILES TAB (With Grouping Logic)
                    VStack(spacing: 0) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField("Search installed profiles...", text: $profileSearch)
                                .textFieldStyle(.plain)
                            if !profileSearch.isEmpty {
                                Button(action: { profileSearch = "" }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.1)), alignment: .bottom)
                        
                        // Grouped List
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                if let profiles = detail.configurationProfiles, !profiles.isEmpty {
                                    let filtered = profiles.filter {
                                        profileSearch.isEmpty ||
                                        ($0.displayName?.localizedCaseInsensitiveContains(profileSearch) ?? false) ||
                                        ($0.identifier?.localizedCaseInsensitiveContains(profileSearch) ?? false)
                                    }
                                    
                                    if filtered.isEmpty {
                                        ContentUnavailableView(
                                            "No Matching Profiles",
                                            systemImage: "doc.text.magnifyingglass",
                                            description: Text("Try a different search term.")
                                        )
                                        .padding(.top, 40)
                                    } else {
                                        // 1. MDM Profile Group
                                        let mdmProfiles = filtered.filter { $0.displayName == "MDM Profile" }
                                        if !mdmProfiles.isEmpty {
                                            InspectorProfileGroup(title: "Management Profile", profiles: mdmProfiles, api: api, profileToInspect: $profileToInspect)
                                        }
                                        
                                        // 2. Configuration Profiles Group (The Rest)
                                        let configProfiles = filtered.filter { $0.displayName != "MDM Profile" }
                                        if !configProfiles.isEmpty {
                                            InspectorProfileGroup(title: "Configuration Profiles", profiles: configProfiles, api: api, profileToInspect: $profileToInspect)
                                        }
                                    }
                                } else {
                                    ContentUnavailableView(
                                        "No Profiles",
                                        systemImage: "doc.text.magnifyingglass",
                                        description: Text("No configuration profiles reported.")
                                    )
                                    .padding(.top, 40)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .frame(width: 500, height: 650)
        .liquidGlass(.panel)
        .task {
            do {
                self.detail = try await api.fetchComputerDetail(id: computerId)
                self.isLoading = false
            } catch {
                print("Error: \(error)")
                self.isLoading = false
            }
        }
        // FIX: Explicit self.api
        .sheet(item: $profileToInspect) { selection in
            ProfileInspectorView(profileId: selection.id, api: self.api)
        }
    }
}

// MARK: - Subcomponents

// Group Component for Profiles (Collapsible Style)
struct InspectorProfileGroup: View {
    let title: String
    let profiles: [ComputerProfile]
    @ObservedObject var api: JamfAPIService
    @Binding var profileToInspect: InspectorSelection?
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: title == "Management Profile" ? "lock.shield.fill" : "doc.on.doc.fill")
                        .foregroundColor(title == "Management Profile" ? .green : .blue)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(profiles.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // List Items
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(profiles) { profile in
                        HStack(alignment: .top, spacing: 10) {
                            // Icon based on type
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.secondary)
                                .font(.title3)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? "Unknown Profile")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                if let id = profile.identifier {
                                    Text(id)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fontDesign(.monospaced)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer()
                            
                            // Context Menu Hint Icon
                            Image(systemName: "ellipsis.circle")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle()) // Makes the whole row clickable
                        .contextMenu {
                            if let jamfIdString = profile.jamfId, let jamfId = Int(jamfIdString) {
                                Button("Inspect Profile") {
                                    profileToInspect = InspectorSelection(id: jamfId)
                                }
                            } else {
                                Text("Cannot Inspect (System Profile)")
                            }
                        }
                        
                        // Divider between items
                        if profile.id != profiles.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
    }
}

// Reusable Info Row (Existing)
struct InfoSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                content
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.1), lineWidth: 1))
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary).font(.callout)
            Spacer()
            Text(value).fontWeight(.medium).font(.callout)
        }
    }
}
