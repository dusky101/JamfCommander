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
    
    // Data
    @State private var detail: ComputerInventoryRecord?
    @State private var scripts: [ScriptRecord] = [] // Real Script Data
    @State private var policies: [Policy] = [] // Real Policy Data
    @State private var isLoading = true
    
    // View State
    @State private var selectedTab = 0 // 0=Info, 1=Profiles, 2=Scripts, 3=Policies
    @State private var profileSearch = ""
    @State private var scriptSearch = ""
    @State private var policySearch = ""
    
    // Inspection Sheets
    @State private var profileToInspect: InspectorSelection?
    @State private var scriptToInspect: InspectorSelection?
    @State private var policyToInspect: InspectorSelection?
    
    var body: some View {
        InspectorShell(
            title: "DEVICE",
            id: "#\(computerId)",
            headerText: detail?.general?.name ?? "Loading...",
            icon: nil,
            isLoading: isLoading,
            onClose: { dismiss() }
        ) {
            // --- TAB PICKER ---
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Profiles").tag(1)
                    Text("Scripts").tag(2)
                    Text("Policies").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()
                .background(.ultraThinMaterial)
                
                Divider()
                
                // --- TABS ---
                switch selectedTab {
                case 0: infoTab
                case 1: profilesTab
                case 2: scriptsTab
                case 3: policiesTab
                default: EmptyView()
                }
            }
        }
        .task {
            await loadData()
        }
        // Sheets
        .sheet(item: $profileToInspect) { selection in
            ProfileInspectorView(profileId: selection.id, api: api)
        }
        .sheet(item: $scriptToInspect) { selection in
            ScriptInspectorView(scriptId: selection.id, api: api)
        }
        .sheet(item: $policyToInspect) { selection in
            PoliciesInspectorView(policyId: selection.id, api: api)
        }
    }
    
    func loadData() async {
        do {
            // Fetch Computer Detail, Scripts, and Policies in parallel
            async let detailCall = api.fetchComputerDetail(id: computerId)
            async let scriptsCall = api.fetchScripts()
            async let policiesCall = api.fetchPolicies()
            
            let (fetchedDetail, fetchedScripts, fetchedPolicies) = try await (detailCall, scriptsCall, policiesCall)
            
            self.detail = fetchedDetail
            self.scripts = fetchedScripts
            self.policies = fetchedPolicies
            self.isLoading = false
        } catch {
            print("Error loading inspector data: \(error)")
            self.isLoading = false
        }
    }
    
    // MARK: - 1. Info Tab
    var infoTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hardware
                InfoSection(title: "Hardware", icon: "cpu") {
                    if let hardware = detail?.hardware {
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
                    if let os = detail?.operatingSystem {
                        InfoRow(label: "OS Version", value: "\(os.name ?? "macOS") \(os.version ?? "")")
                        InfoRow(label: "Build", value: os.build ?? "Unknown")
                        InfoRow(label: "FileVault", value: os.fileVault2Status ?? "Unknown")
                    }
                }
                
                // Status
                InfoSection(title: "Status", icon: "antenna.radiowaves.left.and.right") {
                    if let general = detail?.general {
                        InfoRow(label: "IP Address", value: general.lastReportedIp ?? "Unknown")
                        InfoRow(label: "Last Contact", value: general.lastContactTime ?? "Never")
                        InfoRow(label: "Managed", value: (general.remoteManagement?.managed ?? false) ? "Yes" : "No")
                        if let user = general.remoteManagement?.managementUsername {
                            InfoRow(label: "Mgmt Account", value: user)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - 2. Profiles Tab
    var profilesTab: some View {
        VStack(spacing: 0) {
            // Search
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
            
            // List
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let profiles = detail?.configurationProfiles, !profiles.isEmpty {
                        let filtered = profiles.filter {
                            profileSearch.isEmpty ||
                            ($0.displayName?.localizedCaseInsensitiveContains(profileSearch) ?? false) ||
                            ($0.identifier?.localizedCaseInsensitiveContains(profileSearch) ?? false)
                        }
                        
                        if filtered.isEmpty {
                            ContentUnavailableView("No Matching Profiles", systemImage: "doc.text.magnifyingglass")
                                .padding(.top, 40)
                        } else {
                            // Groups
                            let mdmProfiles = filtered.filter { $0.displayName == "MDM Profile" }
                            if !mdmProfiles.isEmpty {
                                InspectorProfileGroup(title: "Management Profile", profiles: mdmProfiles, api: api, profileToInspect: $profileToInspect)
                            }
                            
                            let configProfiles = filtered.filter { $0.displayName != "MDM Profile" }
                            if !configProfiles.isEmpty {
                                InspectorProfileGroup(title: "Configuration Profiles", profiles: configProfiles, api: api, profileToInspect: $profileToInspect)
                            }
                        }
                    } else {
                        ContentUnavailableView("No Profiles", systemImage: "doc.text.magnifyingglass")
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - 3. Scripts Tab (Real Data)
    var scriptsTab: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search available scripts...", text: $scriptSearch)
                    .textFieldStyle(.plain)
                if !scriptSearch.isEmpty {
                    Button(action: { scriptSearch = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    let filteredScripts = scripts.filter {
                        scriptSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(scriptSearch)
                    }
                    
                    if filteredScripts.isEmpty {
                        ContentUnavailableView("No Scripts Found", systemImage: "applescript")
                            .padding(.top, 40)
                    } else {
                        ForEach(filteredScripts) { script in
                            HStack(alignment: .center, spacing: 12) {
                                // Icon
                                Image(systemName: "applescript.fill")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                                
                                // Text
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(script.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 6) {
                                        Text("ID: \(script.id)")
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .padding(3)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(4)
                                        
                                        if let cat = script.categoryName {
                                            Text("•")
                                            Text(cat)
                                        }
                                    }
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Inspect Button
                                Button("Inspect") {
                                    scriptToInspect = InspectorSelection(id: script.intId)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(8)
                            // Context Menu
                            .contextMenu {
                                Button("Inspect Script") {
                                    scriptToInspect = InspectorSelection(id: script.intId)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - 4. Policies Tab (Real Data)
    var policiesTab: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search policies...", text: $policySearch)
                    .textFieldStyle(.plain)
                if !policySearch.isEmpty {
                    Button(action: { policySearch = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Divider(), alignment: .bottom)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Filter policies that apply to this computer
                    let applicablePolicies = policies.filter { policy in
                        guard let scope = policy.scope else { return false }
                        
                        // Include if targeting all computers
                        if scope.all_computers {
                            return true
                        }
                        
                        // Include if this computer is in the targets list
                        if let computers = scope.computers {
                            return computers.contains { $0.id == computerId }
                        }
                        
                        return false
                    }
                    
                    // Apply search filter
                    let filteredPolicies = applicablePolicies.filter {
                        policySearch.isEmpty || $0.name.localizedCaseInsensitiveContains(policySearch)
                    }
                    
                    if filteredPolicies.isEmpty {
                        ContentUnavailableView(
                            policySearch.isEmpty ? "No Policies Apply" : "No Matching Policies",
                            systemImage: "scroll",
                            description: Text(policySearch.isEmpty ? "This computer is not targeted by any policies." : "Try adjusting your search.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(filteredPolicies) { policy in
                            HStack(alignment: .center, spacing: 12) {
                                // Icon
                                Image(systemName: policy.scope?.all_computers == true ? "globe" : "target")
                                    .foregroundColor(policy.enabled ? .purple : .secondary)
                                    .font(.title3)
                                
                                // Text
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(policy.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    HStack(spacing: 6) {
                                        Text("ID: \(policy.id)")
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .padding(3)
                                            .background(Color.gray.opacity(0.1))
                                            .cornerRadius(4)
                                        
                                        if let category = policy.categoryName {
                                            Text("•")
                                            Text(category)
                                        }
                                        
                                        Text("•")
                                        Text(policy.scope?.all_computers == true ? "All Computers" : "Targeted")
                                    }
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Status Badge
                                if policy.enabled {
                                    Text("Active")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                } else {
                                    Text("Disabled")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.1))
                                        .foregroundColor(.secondary)
                                        .cornerRadius(4)
                                }
                                
                                // Inspect Button
                                Button("Inspect") {
                                    policyToInspect = InspectorSelection(id: policy.id)
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(8)
                            // Context Menu
                            .contextMenu {
                                Button("Inspect Policy") {
                                    policyToInspect = InspectorSelection(id: policy.id)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Local Subcomponents
struct InspectorProfileGroup: View {
    let title: String
    let profiles: [ComputerProfile]
    @ObservedObject var api: JamfAPIService
    @Binding var profileToInspect: InspectorSelection?
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(profiles) { profile in
                        HStack(alignment: .top, spacing: 10) {
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
                            Image(systemName: "ellipsis.circle")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                        .contextMenu {
                            if let jamfIdString = profile.jamfId, let jamfId = Int(jamfIdString) {
                                Button("Inspect Profile") {
                                    profileToInspect = InspectorSelection(id: jamfId)
                                }
                            } else {
                                Text("Cannot Inspect (System Profile)")
                            }
                        }
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
