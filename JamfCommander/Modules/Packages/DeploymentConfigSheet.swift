//
//  DeploymentConfigSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers

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

// MARK: - Deployment Plan

/// Everything the sheet collects for one "Add to Jamf" run. Passed as a single value so the
/// callback doesn't grow another positional argument each time the flow gains an option.
struct InstallomatorDeploymentPlan {
    var categoryName: String
    var scriptID: String
    var featureOnMainPage: Bool
    var displayInSelfServiceCategory: Bool
    var scope: DeploymentScopeConfig
    var policyNameTemplate: String

    /// An icon already in Jamf's icon library, attached to each policy after it is created.
    /// `nil` — the default — leaves the policies without a Self Service icon, exactly as before.
    var iconID: Int?

    /// The policies to create **per selected label**. The default single unpinned variant reproduces
    /// today's behaviour exactly; several variants means one policy per pinned version.
    var variants: [InstallomatorPolicyVariant] = [.unpinned]
}

struct DeploymentConfigSheet: View {
    @ObservedObject var api: JamfAPIService

    /// The labels this run will create policies for, so their names can be resolved and checked
    /// against Jamf before anything is written.
    let pendingItems: [InstallomatorItem]

    var onConfirm: (InstallomatorDeploymentPlan) -> Void
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
    @State private var showNameReview = false

    // Version pinning (single-label runs only)
    @State private var isPinningVersions = false
    @State private var versionsText = ""
    @State private var overrides: [InstallomatorOverride] = [InstallomatorOverride()]
    
    // Self Service Options
    @State private var featureOnMainPage = false
    @State private var displayInSelfServiceCategory = true

    // Self Service Icon — uploaded (or picked) once per run; only the id reaches the batch
    @State private var selectedIcon: SelfServiceIcon?
    @State private var iconImage: NSImage?
    @State private var isUploadingIcon = false
    @State private var iconError: String?
    @State private var showIconPicker = false
    
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

    /// Whether version pinning is on offer. Overrides describe one app's downloads, so they only
    /// make sense for a run containing a single label — a pinned Python URL is meaningless for Firefox.
    private var supportsVersionPinning: Bool { pendingItems.count == 1 }

    /// The versions typed by the administrator, in the order given.
    private var pinnedVersions: [String] {
        guard supportsVersionPinning, isPinningVersions else { return [] }
        return InstallomatorOverrides.parseVersions(versionsText)
    }

    /// Anything that must be fixed before deploying.
    private var pinningIssues: [InstallomatorOverrides.Issue] {
        guard supportsVersionPinning, isPinningVersions else { return [] }
        return InstallomatorOverrides.issues(
            overrides: overrides,
            versions: pinnedVersions,
            nameTemplate: policyNameTemplate
        )
    }

    /// The policies this run will create for each label.
    private var plannedVariants: [InstallomatorPolicyVariant] {
        guard supportsVersionPinning, isPinningVersions else { return [.unpinned] }
        return InstallomatorOverrides.variants(overrides: overrides, versions: pinnedVersions)
    }

    /// The policy name for one label and one variant.
    private func resolvedName(for item: InstallomatorItem, variant: InstallomatorPolicyVariant) -> String {
        JamfAPIService.resolvePolicyName(
            template: policyNameTemplate,
            appName: item.displayName,
            version: variant.version
        )
    }

    /// One policy this run will create. Identified by position rather than by name, because two
    /// variants can briefly resolve to the same name while the template is being edited.
    private struct PlannedPolicy: Identifiable {
        let id: Int
        let item: InstallomatorItem
        let name: String
    }

    /// Every policy this run would create — one row per label per variant. Everything downstream
    /// (the duplicate check, the review list, the confirmation count) reads this, so pinning can
    /// never make those three disagree.
    private var plannedPolicies: [PlannedPolicy] {
        pendingItems
            .flatMap { item in plannedVariants.map { (item, $0) } }
            .enumerated()
            .map { index, unit in
                PlannedPolicy(id: index, item: unit.0, name: resolvedName(for: unit.0, variant: unit.1))
            }
    }

    /// The policy names this run would create, resolved from the current template.
    private var resolvedPolicyNames: [String] {
        plannedPolicies.map(\.name)
    }

    /// Labels whose app name is still one unbroken word, so the resulting policy name reads like the
    /// raw Installomator label ("Install Mysqlworkbenchce"). Worth a look before it is written.
    private var itemsWithAwkwardNames: [InstallomatorItem] {
        pendingItems.filter { InstallomatorLabelFormatter.looksUnsegmented($0.displayName) }
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

    /// Searches on the same rule as the Computers dashboard — name, serial, assigned user or email —
    /// so an administrator can find a Mac by whoever it belongs to.
    var filteredComputers: [ComputerInventoryRecord] {
        computers.filter { $0.matches(scopeSearchText) }
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
                                
                                Text("Use **{appName}** for the application name, and **{version}** when pinning versions below.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if !policyNameTemplate.isEmpty, let first = plannedPolicies.first {
                                    HStack(spacing: 4) {
                                        Text("Preview:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(first.name)
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .italic()
                                    }
                                }

                                nameReview
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

                                iconChooser
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

                            versionPinningSection

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
                                            Text("Icon:").foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                if let iconImage {
                                                    Image(nsImage: iconImage)
                                                        .resizable()
                                                        .interpolation(.high)
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(width: 18, height: 18)
                                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                                }
                                                Text(iconSummaryText).bold()
                                            }
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
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(pendingItems.count) \(pendingItems.count == 1 ? "label" : "labels") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if plannedPolicies.count != pendingItems.count {
                        Text("\(plannedPolicies.count) policies will be created")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                Button("Deploy Policies", action: requestDeployment)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedCategory == nil || selectedScriptID == nil || !isScopeValid
                              || policyNameTemplate.isEmpty || !pinningIssues.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 750, height: 620)
        .appBackground()
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showIconPicker) {
            SelfServiceIconPickerView(
                api: api,
                onPick: { icon in
                    showIconPicker = false
                    selectedIcon = icon
                    iconError = nil
                    iconImage = nil
                    if let iconID = icon.id {
                        loadIconPreview(id: iconID)
                    }
                },
                onCancel: { showIconPicker = false }
            )
        }
        .onAppear(perform: loadData)
    }

    // MARK: - Version Pinning

    /// Optional per-label version pinning: one policy per version, each carrying its own
    /// Installomator argument overrides in parameter7–parameter11.
    ///
    /// The app cannot offer a list of *available* versions — labels discover those by scraping the
    /// vendor's site on the Mac at install time, and replicating that here would mean per-vendor
    /// scraping logic that silently goes stale. So the administrator supplies the versions and the
    /// URL pattern once, and the app expands, validates and previews.
    @ViewBuilder
    private var versionPinningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("6. Version Pinning (Advanced)")
                .font(.caption).fontWeight(.bold).foregroundColor(.secondary)

            if !supportsVersionPinning {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Available when a single label is selected — a pinned download URL describes one application, so it can't apply to a mixed batch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
            } else {
                Picker("", selection: $isPinningVersions) {
                    Text("Let Installomator decide (recommended)").tag(false)
                    Text("Pin specific versions").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if isPinningVersions {
                    pinningEditor
                }
            }
        }
    }

    @ViewBuilder
    private var pinningEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Versions — one policy is created for each")
                    .font(.caption)
                TextField("e.g. 3.11.9, 3.12.7, 3.13.1", text: $versionsText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .accessibilityLabel("Versions to pin")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Installomator overrides — use {version} where the version appears")
                    .font(.caption)

                ForEach($overrides) { $override in
                    HStack(spacing: 6) {
                        Picker("", selection: $override.key) {
                            Text("Choose…").tag("")
                            ForEach(InstallomatorOverrides.allowedKeys, id: \.self) { key in
                                Text(key).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 145)
                        .accessibilityLabel("Override variable")

                        TextField("value", text: $override.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .accessibilityLabel("Override value")

                        Button {
                            overrides.removeAll { $0.id == override.id }
                            if overrides.isEmpty { overrides = [InstallomatorOverride()] }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove this override")
                    }
                }

                Button {
                    overrides.append(InstallomatorOverride())
                } label: {
                    Label("Add Override", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(overrides.count >= InstallomatorOverrides.maximumOverrides)
                .help("A policy has room for five overrides (parameter7 to parameter11).")
            }

            pinningPreview

            if !pinningIssues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(pinningIssues, id: \.self) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Label("A pinned download URL stops working the moment the vendor moves or removes the file, and the policy will then fail on every Mac. Pinning an architecture-specific URL installs the wrong binary on the other architecture — for a genuine split, create one policy per architecture and scope each to an architecture-based smart group.", systemImage: "exclamationmark.shield")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06))
        .cornerRadius(8)
    }

    /// Exactly what will be written, per policy — no surprises at deploy time.
    @ViewBuilder
    private var pinningPreview: some View {
        if let item = pendingItems.first, !plannedVariants.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Will create \(plannedVariants.count) \(plannedVariants.count == 1 ? "policy" : "policies"):")
                    .font(.caption)
                    .fontWeight(.medium)

                ForEach(plannedVariants, id: \.self) { variant in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resolvedName(for: item, variant: variant))
                            .font(.caption)
                            .foregroundColor(.blue)
                        ForEach(Array(variant.overrides.enumerated()), id: \.offset) { index, parameter in
                            Text("parameter\(index + 7)  \(parameter)")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    // MARK: - Policy Name Review

    /// Every policy name this run would create, so an awkward one is caught here rather than after
    /// it exists in Jamf. Installomator labels are lowercase and unpunctuated, and the app can only
    /// tidy the ones it recognises — so the names it is least sure about are marked for a look.
    @ViewBuilder
    private var nameReview: some View {
        if !pendingItems.isEmpty {
            DisclosureGroup(isExpanded: $showNameReview) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plannedPolicies) { planned in
                        let needsChecking = InstallomatorLabelFormatter.looksUnsegmented(planned.item.displayName)
                        HStack(spacing: 6) {
                            Image(systemName: needsChecking ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(needsChecking ? .orange : .green.opacity(0.7))
                            Text(planned.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(planned.item.label)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(needsChecking
                            ? "\(planned.name) — check this name"
                            : planned.name)
                    }
                }
                .padding(.top, 4)
                .frame(maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack(spacing: 6) {
                    Text("Review policy names (\(plannedPolicies.count))")
                        .font(.caption)
                    if !itemsWithAwkwardNames.isEmpty {
                        Text("\(itemsWithAwkwardNames.count) to check")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }
            .help("Names come from the Installomator label. Anything marked in amber is still one unbroken word — worth reading before it becomes a policy name.")
        }
    }

    // MARK: - Self Service Icon

    /// One icon for the whole run: no icon (the default), a local image uploaded to Jamf's icon
    /// library, or an existing Jamf icon reused by id. Whichever route is taken, the upload or
    /// lookup happens **once here** and only the resulting id is handed to the batch.
    private var iconChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                iconPreview

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedIcon?.id == nil ? "No icon" : (selectedIcon?.filename ?? "Existing Jamf icon"))
                        .font(.callout)
                        .fontWeight(.medium)
                    if let iconID = selectedIcon?.id {
                        Text("Icon ID \(iconID) — applied to every policy in this run")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Policies will be created without a Self Service icon.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isUploadingIcon {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button { pickAndUploadIcon() } label: {
                    Label("Upload Image…", systemImage: "square.and.arrow.up")
                }
                .disabled(isUploadingIcon)

                Button { showIconPicker = true } label: {
                    Label("Reuse Existing…", systemImage: "photo.on.rectangle")
                }
                .disabled(isUploadingIcon)

                if selectedIcon != nil {
                    Button {
                        selectedIcon = nil
                        iconImage = nil
                        iconError = nil
                    } label: {
                        Label("Remove", systemImage: "xmark.circle")
                    }
                    .disabled(isUploadingIcon)
                }

                Spacer()
            }

            if let iconError {
                Label(iconError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One line describing the chosen icon, for the summary box.
    private var iconSummaryText: String {
        guard let iconID = selectedIcon?.id else { return "None" }
        if let filename = selectedIcon?.filename, !filename.isEmpty { return filename }
        return "Icon ID \(iconID)"
    }

    @ViewBuilder
    private var iconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel(iconImage == nil ? "No Self Service icon chosen" : "Chosen Self Service icon")
    }

    /// Uploading only adds the image to Jamf's icon library — it changes no policy and reaches no
    /// device, so (as in `PolicySelfServiceEditorView`) it isn't itself gated by a confirmation.
    /// Attaching it to real policies happens later, behind the deployment confirmation.
    private func pickAndUploadIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .gif, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Self Service icon (PNG or GIF recommended, ≈512×512)."
        panel.prompt = "Upload"

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        isUploadingIcon = true
        iconError = nil
        let filename = fileURL.lastPathComponent
        let mime = mimeType(forPathExtension: fileURL.pathExtension)

        Task {
            do {
                let data = try Data(contentsOf: fileURL)
                let icon = try await api.uploadIcon(imageData: data, filename: filename, mimeType: mime)
                await MainActor.run {
                    isUploadingIcon = false
                    if let iconID = icon.id {
                        // Cache the bytes we just uploaded so the preview is instant.
                        IconImageCache.shared.store(id: iconID, data: data)
                    }
                    selectedIcon = icon
                    iconImage = NSImage(data: data)
                }
            } catch {
                await MainActor.run {
                    isUploadingIcon = false
                    iconError = "Couldn't upload the icon. Check the image format (PNG, GIF or JPEG) and your Jamf permissions, then try again."
                }
            }
        }
    }

    private func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    /// Loads the preview for an icon reused from Jamf (the upload path already has the bytes).
    private func loadIconPreview(id: Int) {
        Task {
            let image = await IconImageCache.shared.loadImage(id: id, using: api)
            await MainActor.run { iconImage = image }
        }
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

        let count = plannedPolicies.count
        let noun = count == 1 ? "policy" : "policies"

        var message = "\(count) Self Service \(noun) will be created in Jamf under '\(category.name)', scoped to \(scopeConfig.summaryText.lowercased())."
        if let iconID = selectedIcon?.id {
            message += " Icon \(iconID) will be attached to each one."
        }
        if !pinnedVersions.isEmpty {
            message += " Versions pinned: \(pinnedVersions.joined(separator: ", "))."
        }
        if !collidingPolicyNames.isEmpty {
            message += "\n\n\(collidingPolicyNames.count) of these names already exist and will be rejected: \(summarise(collidingPolicyNames))."
        }

        let plan = InstallomatorDeploymentPlan(
            categoryName: category.name,
            scriptID: scriptID,
            featureOnMainPage: featureOnMainPage,
            displayInSelfServiceCategory: displayInSelfServiceCategory,
            scope: scopeConfig,
            policyNameTemplate: policyNameTemplate,
            iconID: selectedIcon?.id,
            variants: plannedVariants
        )

        confirmation = ConfirmationData(
            title: "Create \(count) \(noun)?",
            message: message,
            actionTitle: "Create \(noun.capitalized)",
            role: nil,
            action: { onConfirm(plan) }
        )
    }

    // MARK: - Scope Pickers
    
    private var scopeComputerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by name, serial, user or email...", text: $scopeSearchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search computers")
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
                    if filteredComputers.isEmpty {
                        Text(scopeSearchText.isEmpty ? "No computers found." : "No computers match “\(scopeSearchText)”.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(filteredComputers) { computer in
                        let isSelected = scopeConfig.selectedComputerIDs.contains(computer.id)
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray.opacity(0.4))
                            ComputerIdentityRow(computer: computer)
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
                        // The whole row is the toggle, so expose it as one selectable element
                        // rather than an unlabelled tick image beside some text.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint("Adds or removes this computer from the deployment scope")
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
