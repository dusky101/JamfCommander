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
    case smartComputerGroups = "Smart Groups"
    case staticComputerGroups = "Static Groups"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .allComputers: return "desktopcomputer"
        case .specificComputers: return "laptopcomputer"
        case .smartComputerGroups: return "gearshape.2.fill"
        case .staticComputerGroups: return "person.3.fill"
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
        case .smartComputerGroups, .staticComputerGroups:
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
        case .smartComputerGroups:
            return "\(selectedGroupIDs.count) smart group(s)"
        case .staticComputerGroups:
            return "\(selectedGroupIDs.count) static group(s)"
        }
    }
}

struct DeploymentConfigSheet: View {
    @ObservedObject var api: JamfAPIService

    /// The labels this run will create policies for, so their names can be resolved and checked
    /// against Jamf before anything is written.
    let pendingItems: [InstallomatorItem]

    // Callbacks: (CategoryName, ScriptID, FeatureOnMain, DisplayInCategory, ScopeConfig, NameTemplate)
    var onConfirm: (String, String, Bool, Bool, DeploymentScopeConfig, String) -> Void
    var onCancel: () -> Void

    // Data State
    @State private var categories: [Category] = []
    @State private var scripts: [ScriptRecord] = []
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var computerGroups: [ComputerGroup] = []
    @State private var isLoading = true

    // Pre-flight duplicate-name check
    @State private var existingPolicyNameKeys: Set<String> = []
    @State private var nameCheckFailed = false

    // Confirmation before writing to the live tenant
    @State private var confirmation: ConfirmationData?

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
    @State private var categoryError: String?
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Pre-flight Duplicate Check

    /// The policy names this run would create, resolved from the current template.
    private var resolvedPolicyNames: [String] {
        pendingItems.map {
            policyNameTemplate.replacingOccurrences(of: "{appName}", with: $0.displayName)
        }
    }

    /// Names Jamf already holds. Creating these would be rejected with a duplicate-name conflict,
    /// so they are surfaced here rather than collected as failures after the batch has run.
    private var collidingPolicyNames: [String] {
        guard !existingPolicyNameKeys.isEmpty else { return [] }
        return resolvedPolicyNames.filter {
            existingPolicyNameKeys.contains(PolicyNameMatching.exactKey($0))
        }
    }

    /// "A, B and 3 more" — keeps a long list readable in a banner or dialog.
    private func summarise(_ names: [String], showing limit: Int = 3) -> String {
        guard names.count > limit else {
            return names.formatted(.list(type: .and))
        }
        let shown = names.prefix(limit).formatted(.list(type: .and))
        return "\(shown) and \(names.count - limit) more"
    }

    var filteredComputers: [ComputerInventoryRecord] {
        if scopeSearchText.isEmpty { return computers }
        return computers.filter {
            ($0.general?.name ?? "").localizedCaseInsensitiveContains(scopeSearchText)
        }
    }
    
    var filteredGroups: [ComputerGroup] {
        let groupsForScope = computerGroups.filter { group in
            switch scopeConfig.scopeType {
            case .smartComputerGroups:
                return group.smartGroup == true
            case .staticComputerGroups:
                return group.smartGroup != true
            case .allComputers, .specificComputers:
                return false
            }
        }
        
        if scopeSearchText.isEmpty { return groupsForScope }
        return groupsForScope.filter {
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
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    TextField("Name", text: $newCategoryName)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Save") { createCategory() }
                                        .disabled(newCategoryName.isEmpty || isSavingCategory)
                                    Button(action: {
                                        isCreatingCategory = false
                                        categoryError = nil
                                    }) {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Cancel new category")
                                }

                                if let categoryError {
                                    Label(categoryError, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
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
                                    scopeConfig.selectedGroupIDs.removeAll()
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
                                    
                                case .smartComputerGroups, .staticComputerGroups:
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

            preflightBanner

            // Footer
            HStack {
                Text("\(pendingItems.count) \(pendingItems.count == 1 ? "label" : "labels") selected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Deploy Policies", action: requestDeployment)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedCategory == nil || selectedScriptID == nil || !isScopeValid || policyNameTemplate.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 750, height: 620)
        .appBackground()
        .commanderConfirmation(data: $confirmation)
        .onAppear(perform: loadData)
    }

    // MARK: - Pre-flight Banner

    /// Warns about name clashes before anything is written, so the administrator can change the
    /// template or cancel and deselect — rather than collecting rejections after the fact.
    @ViewBuilder
    private var preflightBanner: some View {
        if !collidingPolicyNames.isEmpty {
            banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                text: "\(collidingPolicyNames.count) of \(pendingItems.count) policy names already exist in Jamf and will be rejected: \(summarise(collidingPolicyNames)). Change the name template, or cancel and deselect them."
            )
        } else if nameCheckFailed {
            banner(
                icon: "info.circle.fill",
                tint: .secondary,
                text: "Could not check Jamf for existing policy names. Any name that is already taken will be reported after the deployment."
            )
        }
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Confirmation

    /// Policy creation writes to the live tenant and installs software on real Macs, so the
    /// administrator confirms exactly what is about to happen first.
    private func requestDeployment() {
        guard let category = selectedCategory, let scriptID = selectedScriptID else { return }

        let count = pendingItems.count
        let noun = count == 1 ? "policy" : "policies"

        var message = "\(count) Self Service \(noun) will be created in Jamf under '\(category.name)', scoped to \(scopeConfig.summaryText.lowercased())."
        if !collidingPolicyNames.isEmpty {
            message += "\n\n\(collidingPolicyNames.count) of these names already exist and will be rejected: \(summarise(collidingPolicyNames))."
        }

        confirmation = ConfirmationData(
            title: "Create \(count) \(noun)?",
            message: message,
            actionTitle: "Create \(noun.capitalized)",
            role: nil,
            action: {
                onConfirm(
                    category.name,
                    scriptID,
                    featureOnMainPage,
                    displayInSelfServiceCategory,
                    scopeConfig,
                    policyNameTemplate
                )
            }
        )
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
                TextField("Search \(scopeConfig.scopeType.rawValue.lowercased())...", text: $scopeSearchText)
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
                    if filteredGroups.isEmpty {
                        Text(scopeSearchText.isEmpty ? "No \(scopeConfig.scopeType.rawValue.lowercased()) found." : "No matching groups found.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    
                    ForEach(filteredGroups) { group in
                        let isSelected = scopeConfig.selectedGroupIDs.contains(group.id)
                        Button {
                            if isSelected {
                                scopeConfig.selectedGroupIDs.remove(group.id)
                            } else {
                                scopeConfig.selectedGroupIDs.insert(group.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.4))
                                Image(systemName: group.groupTypeIcon)
                                    .foregroundColor(group.smartGroup == true ? .purple : .secondary)
                                Text(group.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(group.groupTypeLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if let memberCount = group.memberCount {
                                    Text("\(memberCount)")
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        case .smartComputerGroups, .staticComputerGroups:
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
                async let fetchedPolicyNames = api.fetchPolicyNames()

                // The duplicate-name check is advisory: if it can't run, the sheet still works and
                // says so in the banner rather than blocking the deployment.
                let policyNames = try? await fetchedPolicyNames

                let (cats, scrts, comps, grps) = try await (fetchedCats, fetchedScripts, fetchedComputers, fetchedGroups)

                await MainActor.run {
                    if let policyNames {
                        self.existingPolicyNameKeys = Set(policyNames.map(PolicyNameMatching.exactKey))
                        self.nameCheckFailed = false
                    } else {
                        self.existingPolicyNameKeys = []
                        self.nameCheckFailed = true
                    }

                    self.categories = cats.sorted { $0.name < $1.name }
                    self.scripts = scrts.sorted { $0.name < $1.name }
                    self.computers = comps
                    self.computerGroups = grps.sorted { lhs, rhs in
                        if lhs.smartGroup != rhs.smartGroup {
                            return lhs.smartGroup == true
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    
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
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingCategory = true
        categoryError = nil

        Task {
            do {
                try await api.createCategory(name: name)
            } catch {
                // Never let a failed write look like a success: keep the field open and say so.
                await MainActor.run {
                    self.categoryError = "Could not create '\(name)' in Jamf. Check the name and your privileges, then try again."
                    self.isSavingCategory = false
                }
                return
            }

            let freshCats = try? await api.fetchCategories()
            await MainActor.run {
                if let fresh = freshCats {
                    self.categories = fresh.sorted { $0.name < $1.name }
                    if let new = fresh.first(where: { $0.name == name }) {
                        self.selectedCategory = new
                    }
                }
                self.isCreatingCategory = false
                self.newCategoryName = ""
                self.categoryError = nil
                self.isSavingCategory = false
            }
        }
    }
}
