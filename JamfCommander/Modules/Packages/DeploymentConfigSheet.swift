//
//  DeploymentConfigSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI

// MARK: - Scope Configuration Model

enum DeploymentScopeType: String, CaseIterable, Identifiable {
    case allComputers = "All Computers"
    case specificComputers = "Specific Computers"
    case computerGroups = "Computer Groups"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .allComputers: return "desktopcomputer"
        case .specificComputers: return "laptopcomputer"
        case .computerGroups: return "person.3.fill"
        }
    }
}

struct DeploymentScopeConfig {
    var scopeType: DeploymentScopeType = .allComputers
    var selectedComputerIDs: Set<String> = []   // Pro API uses String IDs
    var selectedGroupIDs: Set<Int> = []
    
    /// Generates the XML <scope> block for the Jamf Classic API
    func toScopeXML() -> String {
        switch scopeType {
        case .allComputers:
            return """
                <scope>
                    <all_computers>true</all_computers>
                </scope>
            """
        case .specificComputers:
            let computersXML = selectedComputerIDs.map {
                "<computer><id>\($0)</id></computer>"
            }.joined(separator: "\n                    ")
            return """
                <scope>
                    <all_computers>false</all_computers>
                    <computers>
                        \(computersXML)
                    </computers>
                </scope>
            """
        case .computerGroups:
            let groupsXML = selectedGroupIDs.map {
                "<computer_group><id>\($0)</id></computer_group>"
            }.joined(separator: "\n                    ")
            return """
                <scope>
                    <all_computers>false</all_computers>
                    <computer_groups>
                        \(groupsXML)
                    </computer_groups>
                </scope>
            """
        }
    }
    
    /// Human-readable summary for the UI
    var summaryText: String {
        switch scopeType {
        case .allComputers:
            return "All Computers"
        case .specificComputers:
            return "\(selectedComputerIDs.count) computer(s)"
        case .computerGroups:
            return "\(selectedGroupIDs.count) group(s)"
        }
    }
}

struct DeploymentConfigSheet: View {
    @ObservedObject var api: JamfAPIService
    
    // Callbacks: (CategoryName, ScriptID, FeatureOnMain, DisplayInCategory, ScopeConfig, NameTemplate)
    var onConfirm: (String, String, Bool, Bool, DeploymentScopeConfig, String) -> Void
    var onCancel: () -> Void
    
    // Data State
    @State private var categories: [Category] = []
    @State private var scripts: [ScriptRecord] = []
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var computerGroups: [ComputerGroup] = []
    @State private var isLoading = true
    
    // Selection State
    @State private var selectedCategory: Category?
    @State private var selectedScriptID: String?
    @State private var searchText = ""
    
    // Policy Naming
    @State private var policyNameTemplate = "Install {appName}"
    
    // Self Service Options
    @State private var featureOnMainPage = false
    @State private var displayInSelfServiceCategory = true
    
    // Scope State
    @State private var scopeConfig = DeploymentScopeConfig()
    @State private var scopeSearchText = ""
    
    // Category Creation
    @State private var isCreatingCategory = false
    @State private var newCategoryName = ""
    @State private var isSavingCategory = false
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredComputers: [ComputerInventoryRecord] {
        if scopeSearchText.isEmpty { return computers }
        return computers.filter {
            ($0.general?.name ?? "").localizedCaseInsensitiveContains(scopeSearchText)
        }
    }
    
    var filteredGroups: [ComputerGroup] {
        if scopeSearchText.isEmpty { return computerGroups }
        return computerGroups.filter {
            $0.name.localizedCaseInsensitiveContains(scopeSearchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Deployment Configuration")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if isLoading {
                ProgressView("Loading Jamf Data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    // Left: Category Picker
                    VStack(alignment: .leading, spacing: 0) {
                        Text("1. Select Target Category")
                            .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            .padding(8)
                        
                        List(selection: $selectedCategory) {
                            ForEach(filteredCategories) { category in
                                HStack {
                                    Image(systemName: "folder")
                                    Text(category.name)
                                    Spacer()
                                    if selectedCategory?.id == category.id {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                                .tag(category)
                            }
                        }
                        .searchable(text: $searchText)
                        
                        Divider()
                        
                        // New Category Input
                        if isCreatingCategory {
                            HStack {
                                TextField("Name", text: $newCategoryName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") { createCategory() }
                                    .disabled(newCategoryName.isEmpty || isSavingCategory)
                                Button(action: { isCreatingCategory = false }) {
                                    Image(systemName: "xmark")
                                }.buttonStyle(.plain)
                            }
                            .padding(8)
                        } else {
                            Button(action: { isCreatingCategory = true }) {
                                Label("New Category", systemImage: "plus")
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                    }
                    .frame(width: 220)
                    
                    Divider()
                    
                    // Right: Script, Options & Scope
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            
                            // Script Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("2. Select Installomator Script")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                                
                                if scripts.isEmpty {
                                    Text("No scripts found in Jamf.")
                                        .foregroundColor(.red)
                                } else {
                                    Picker("", selection: $selectedScriptID) {
                                        Text("Select a script...").tag(String?.none)
                                        ForEach(scripts) { script in
                                            Text(script.name).tag(Optional(script.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                }
                            }
                            
                            Divider()
                            
                            // Policy Naming
                            VStack(alignment: .leading, spacing: 8) {
                                Text("3. Policy Name Template")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                                
                                TextField("e.g. Install {appName}", text: $policyNameTemplate)
                                    .textFieldStyle(.roundedBorder)
                                
                                Text("Use **{appName}** as a placeholder for the application name.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if !policyNameTemplate.isEmpty {
                                    HStack(spacing: 4) {
                                        Text("Preview:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(policyNameTemplate.replacingOccurrences(of: "{appName}", with: "Google Chrome"))
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .italic()
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // Self Service Options
                            VStack(alignment: .leading, spacing: 12) {
                                Text("4. Self Service Options")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                                
                                Toggle("Feature on Main Page", isOn: $featureOnMainPage)
                                    .toggleStyle(.switch)
                                
                                Toggle("Display in '\(selectedCategory?.name ?? "Selected Category")'", isOn: $displayInSelfServiceCategory)
                                    .toggleStyle(.switch)
                                    .disabled(selectedCategory == nil)
                            }
                            
                            Divider()
                            
                            // Scope Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("5. Deployment Scope")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                                
                                // Scope Type Picker
                                Picker("Scope", selection: $scopeConfig.scopeType) {
                                    ForEach(DeploymentScopeType.allCases) { type in
                                        Label(type.rawValue, systemImage: type.icon)
                                            .tag(type)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .onChange(of: scopeConfig.scopeType) {
                                    scopeSearchText = ""
                                }
                                
                                // Scope Target Selection
                                switch scopeConfig.scopeType {
                                case .allComputers:
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.shield.fill")
                                            .foregroundColor(.green)
                                        Text("Policy will be scoped to all managed computers.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.green.opacity(0.08))
                                    .cornerRadius(8)
                                    
                                case .specificComputers:
                                    scopeComputerPicker
                                    
                                case .computerGroups:
                                    scopeGroupPicker
                                }
                            }
                            
                            Divider()
                            
                            // Summary Box
                            if let scriptID = selectedScriptID,
                               let script = scripts.first(where: { $0.id == scriptID }) {
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Summary:")
                                        .font(.caption).bold()
                                    
                                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                                        GridRow {
                                            Text("Script:").foregroundColor(.secondary)
                                            Text(script.name).bold()
                                        }
                                        GridRow {
                                            Text("Naming:").foregroundColor(.secondary)
                                            Text(policyNameTemplate).bold()
                                        }
                                        GridRow {
                                            Text("Self Service:").foregroundColor(.secondary)
                                            Text(featureOnMainPage ? "Featured" : "Standard")
                                        }
                                        GridRow {
                                            Text("Scope:").foregroundColor(.secondary)
                                            Text(scopeConfig.summaryText).bold()
                                        }
                                    }
                                    .font(.caption)
                                    .padding()
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Deploy Policies") {
                    if let cat = selectedCategory, let scriptId = selectedScriptID {
                        onConfirm(cat.name, scriptId, featureOnMainPage, displayInSelfServiceCategory, scopeConfig, policyNameTemplate)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCategory == nil || selectedScriptID == nil || !isScopeValid || policyNameTemplate.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 750, height: 620)
        .onAppear(perform: loadData)
    }
    
    // MARK: - Scope Pickers
    
    private var scopeComputerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search computers...", text: $scopeSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            if !scopeConfig.selectedComputerIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                        .foregroundColor(.blue)
                    Text("\(scopeConfig.selectedComputerIDs.count) selected")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        scopeConfig.selectedComputerIDs.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredComputers) { computer in
                        let isSelected = scopeConfig.selectedComputerIDs.contains(computer.id)
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray.opacity(0.4))
                            Text(computer.general?.name ?? "Unknown")
                                .font(.caption)
                            Spacer()
                            if let serial = computer.hardware?.serialNumber {
                                Text(serial)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                scopeConfig.selectedComputerIDs.remove(computer.id)
                            } else {
                                scopeConfig.selectedComputerIDs.insert(computer.id)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        }
    }
    
    private var scopeGroupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search groups...", text: $scopeSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            if !scopeConfig.selectedGroupIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.blue)
                    Text("\(scopeConfig.selectedGroupIDs.count) selected")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        scopeConfig.selectedGroupIDs.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredGroups) { group in
                        let isSelected = scopeConfig.selectedGroupIDs.contains(group.id)
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray.opacity(0.4))
                            Text(group.name)
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                scopeConfig.selectedGroupIDs.remove(group.id)
                            } else {
                                scopeConfig.selectedGroupIDs.insert(group.id)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        }
    }
    
    // MARK: - Validation
    
    private var isScopeValid: Bool {
        switch scopeConfig.scopeType {
        case .allComputers:
            return true
        case .specificComputers:
            return !scopeConfig.selectedComputerIDs.isEmpty
        case .computerGroups:
            return !scopeConfig.selectedGroupIDs.isEmpty
        }
    }
    
    // MARK: - Logic
    
    func loadData() {
        Task {
            // Tiny delay to allow sheet animation to finish before heavy lifting
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            
            do {
                async let fetchedCats = api.fetchCategories()
                async let fetchedScripts = api.fetchScripts()
                async let fetchedComputers = api.fetchComputers()
                async let fetchedGroups = api.fetchComputerGroups()
                
                let (cats, scrts, comps, grps) = try await (fetchedCats, fetchedScripts, fetchedComputers, fetchedGroups)
                
                await MainActor.run {
                    self.categories = cats.sorted { $0.name < $1.name }
                    self.scripts = scrts.sorted { $0.name < $1.name }
                    self.computers = comps
                    self.computerGroups = grps.sorted { $0.name < $1.name }
                    
                    if let match = scrts.first(where: { $0.name.localizedCaseInsensitiveContains("Installomator") }) {
                        self.selectedScriptID = match.id
                    }
                    
                    self.isLoading = false
                }
            } catch {
                print("Error loading config data: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
    
    func createCategory() {
        guard !newCategoryName.isEmpty else { return }
        isSavingCategory = true
        Task {
            try? await api.createCategory(name: newCategoryName)
            let freshCats = try? await api.fetchCategories()
            await MainActor.run {
                if let fresh = freshCats {
                    self.categories = fresh.sorted { $0.name < $1.name }
                    if let new = fresh.first(where: { $0.name == newCategoryName }) {
                        self.selectedCategory = new
                    }
                }
                self.isCreatingCategory = false
                self.newCategoryName = ""
                self.isSavingCategory = false
            }
        }
    }
}
