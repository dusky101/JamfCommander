//
//  PackagesDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI

struct PackagesDashboardView: View {
    @ObservedObject var api: JamfAPIService
    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared

    /// The Installomator script last deployed with, remembered so a policy running it is recognised
    /// as an Installomator deployment even when the script isn't named "Installomator".
    @AppStorage("installomatorScriptID") private var lastUsedScriptID = ""

    // Data
    @State private var allItems: [InstallomatorItem] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // View mode & filtering
    @State private var viewMode: PackageViewMode = .all
    @State private var groupMode: PackageGroupMode = .alphabetical
    @State private var searchText = ""
    
    // Selection
    @State private var selection = Set<String>()
    @State private var lastSelectedID: String?
    
    // Inspector
    @State private var inspectingPolicyID: Int?

    /// The label whose own source is being explained (see `LabelVariantPanel`).
    @State private var explainingItem: InstallomatorItem?
    
    // Deployment
    @State private var isCreatingPolicies = false
    @State private var creationStatus = ""
    @State private var showConfigSheet = false
    @State private var showResultsSheet = false
    @State private var deploymentResults: [OperationResult] = []
    
    // MARK: - Computed Properties
    
    var filteredItems: [InstallomatorItem] {
        let modeFiltered: [InstallomatorItem]
        switch viewMode {
        case .deployed:
            modeFiltered = allItems.filter { $0.isDeployed }
        case .available:
            modeFiltered = allItems.filter { !$0.isDeployed }
        case .all:
            modeFiltered = allItems
        }
        
        if searchText.isEmpty {
            return modeFiltered
        }
        
        return modeFiltered.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var groupedItems: [(key: String, value: [InstallomatorItem])] {
        switch groupMode {
        case .alphabetical:
            let grouped = Dictionary(grouping: filteredItems) { item -> String in
                let first = item.displayName.prefix(1).uppercased()
                return first.rangeOfCharacter(from: .letters) != nil ? first : "#"
            }
            return grouped.sorted { $0.key < $1.key }
        case .category:
            let grouped = Dictionary(grouping: filteredItems) { $0.safeCategory }
            return grouped.sorted { $0.key < $1.key }
        }
    }
    
    var selectedAvailableItems: [InstallomatorItem] {
        allItems.filter { selection.contains($0.id) && !$0.isDeployed }
    }
    
    var deployedCount: Int { allItems.filter { $0.isDeployed }.count }
    var availableCount: Int { allItems.filter { !$0.isDeployed }.count }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            if isLoading {
                LoadingProgressView(message: "Loading Installomator data...")
            } else if let error = loadError {
                errorView(error)
            } else if allItems.isEmpty {
                emptyStateView
            } else {
                searchBar
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedItems, id: \.key) { group in
                            CollapsiblePackageSection(
                                sectionTitle: group.key,
                                groupMode: groupMode,
                                items: group.value,
                                selectedIDs: $selection,
                                onToggle: toggleSelection,
                                onInspect: { policyID in
                                    inspectingPolicyID = policyID
                                },
                                onExplain: { item in
                                    explainingItem = item
                                }
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 60)
                }
            }
            
            if !selection.isEmpty {
                actionFooter
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: refreshCoordinator.token) {
            // Each icon attach is a Classic write, so a batch bumps the refresh token too. Skip the
            // bump while we're mid-deployment or already reloading — `deployPolicies` reloads itself
            // afterwards, and a duplicate full scan would compete for Jamf's rate limit.
            guard !isCreatingPolicies, !isLoading else { return }
            Task { await loadData() }
        }
        .sheet(isPresented: $showConfigSheet) {
            DeploymentConfigSheet(
                api: api,
                pendingItems: selectedAvailableItems,
                onConfirm: { plan in
                    showConfigSheet = false
                    deployPolicies(plan: plan)
                },
                onCancel: {
                    showConfigSheet = false
                }
            )
        }
        .sheet(isPresented: $showResultsSheet) {
            OperationResultView(
                title: "Deployment Results",
                results: deploymentResults,
                onDismiss: {
                    showResultsSheet = false
                    deploymentResults = []
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { inspectingPolicyID != nil },
            set: { if !$0 { inspectingPolicyID = nil } }
        )) {
            if let policyID = inspectingPolicyID {
                PoliciesInspectorView(policyId: policyID, api: api)
            }
        }
        .sheet(item: $explainingItem) { item in
            LabelVariantPanel(api: api, item: item, onDismiss: { explainingItem = nil })
        }
    }
    
    // MARK: - Header
    
    var headerView: some View {
        HStack(spacing: 16) {
            Text("Installomator Manager")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            if !allItems.isEmpty {
                // Group mode picker
                Picker("Group", selection: $groupMode) {
                    ForEach(PackageGroupMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                
                // View mode picker
                Picker("View", selection: $viewMode) {
                    Text("Deployed (\(deployedCount))").tag(PackageViewMode.deployed)
                    Text("Available (\(availableCount))").tag(PackageViewMode.available)
                    Text("All (\(allItems.count))").tag(PackageViewMode.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 320)
                .onChange(of: viewMode) {
                    selection.removeAll()
                    lastSelectedID = nil
                }
                
                Button(action: {
                    Task { await loadData() }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Search Bar
    
    var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps or labels...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            Text("\(filteredItems.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .zIndex(1)
    }
    
    // MARK: - Empty / Error States
    
    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Installomator Data")
                .font(.title3)
                .fontWeight(.medium)
            Text("Could not load labels or policies. Check your connection and try again.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task { await loadData() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Failed to Load Data")
                .font(.title3)
                .fontWeight(.medium)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task { await loadData() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Action Footer
    
    var actionFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(selectedAvailableItems.count) available items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if !creationStatus.isEmpty {
                    Text(creationStatus)
                        .font(.caption)
                        .foregroundColor(creationStatus.contains("Error") || creationStatus.contains("failed") ? .red : .green)
                }
                
                Button(action: { showConfigSheet = true }) {
                    if isCreatingPolicies {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add to Jamf")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreatingPolicies || selectedAvailableItems.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        isLoading = true
        loadError = nil
        selection.removeAll()
        lastSelectedID = nil
        
        do {
            async let labelsResult = api.fetchInstallomatorLabelsFromGitHub()
            async let scriptIDsResult = api.fetchInstallomatorScriptIDs()

            // Script ids widen detection beyond "the policy's script is called Installomator".
            // A failure here only narrows detection, so it degrades rather than failing the load.
            var knownScriptIDs = (try? await scriptIDsResult) ?? []
            if !lastUsedScriptID.isEmpty {
                knownScriptIDs.insert(lastUsedScriptID)
            }

            let scan = try await api.fetchInstallomatorPolicies(knownScriptIDs: knownScriptIDs)
            let allLabels = try await labelsResult

            let deployed = scan.deployed
            let deployedLabels = Set(deployed.map { $0.label.lowercased() })

            // Loose index of every policy name in the tenant, so an app already installed by a
            // policy we can't identify as Installomator is flagged rather than offered blindly.
            var policyNamesByAppKey: [String: String] = [:]
            for name in scan.allPolicyNames {
                policyNamesByAppKey[PolicyNameMatching.appKey(name)] = name
            }

            var items: [InstallomatorItem] = []

            for info in deployed {
                items.append(InstallomatorItem(
                    label: info.label,
                    displayName: InstallomatorLabelFormatter.displayName(for: info.label),
                    isDeployed: true,
                    policyID: info.policyID,
                    policyName: info.policyName,
                    categoryName: info.categoryName,
                    enabled: info.enabled,
                    pinnedVersion: info.pinnedVersion,
                    existingPolicyName: nil
                ))
            }

            for label in allLabels {
                if !deployedLabels.contains(label.lowercased()) {
                    let displayName = InstallomatorLabelFormatter.displayName(for: label)
                    let existingPolicyName = policyNamesByAppKey[PolicyNameMatching.appKey(displayName)]
                        ?? policyNamesByAppKey[PolicyNameMatching.appKey(label)]

                    items.append(InstallomatorItem(
                        label: label,
                        displayName: displayName,
                        isDeployed: false,
                        policyID: nil,
                        policyName: nil,
                        categoryName: nil,
                        enabled: false,
                        pinnedVersion: nil,
                        existingPolicyName: existingPolicyName
                    ))
                }
            }

            items.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            let possiblyDeployedCount = items.filter(\.isPossiblyDeployed).count
            print("[Installomator] Loaded \(items.count) items (\(deployed.count) deployed, \(items.count - deployed.count) available, \(possiblyDeployedCount) possibly deployed)")

            await MainActor.run {
                allItems = items
                isLoading = false
            }
        } catch {
            print("[Installomator] loadData error: \(error.localizedDescription)")
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    // MARK: - Selection Logic
    
    func toggleSelection(id: String) {
        guard let item = allItems.first(where: { $0.id == id }), !item.isDeployed else { return }
        
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        if isShiftPressed, let lastId = lastSelectedID {
            let allVisibleItems = filteredItems
            
            if let lastIndex = allVisibleItems.firstIndex(where: { $0.id == lastId }),
               let currentIndex = allVisibleItems.firstIndex(where: { $0.id == id }) {
                
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                
                let idsToSelect = allVisibleItems[start...end]
                    .filter { !$0.isDeployed }
                    .map { $0.id }
                
                selection.formUnion(idsToSelect)
            }
        } else {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
            lastSelectedID = id
        }
    }
    
    // MARK: - Deployment
    
    func deployPolicies(plan: InstallomatorDeploymentPlan) {
        let itemsToDeploy = selectedAvailableItems
        guard !itemsToDeploy.isEmpty else { return }

        // Remember the script the administrator actually deploys with, so the next scan recognises
        // these policies even if the script is named something other than "Installomator".
        lastUsedScriptID = plan.scriptID

        isCreatingPolicies = true
        creationStatus = "Initialising..."
        deploymentResults = []

        Task {
            var results: [OperationResult] = []

            // One policy per selected label per variant. With the default single unpinned variant
            // this is exactly the old loop; pinning several versions fans out within it, keeping the
            // same inter-item pacing so a four-version run is throttled like a four-label one.
            let work = itemsToDeploy.flatMap { item in
                plan.variants.map { (item: item, variant: $0) }
            }

            for (index, unit) in work.enumerated() {
                let policyName = JamfAPIService.resolvePolicyName(
                    template: plan.policyNameTemplate,
                    appName: unit.item.displayName,
                    version: unit.variant.version
                )

                await MainActor.run {
                    creationStatus = "Deploying \(index + 1) of \(work.count)..."
                }

                do {
                    let newPolicyID = try await api.createInstallomatorPolicyAsync(
                        appName: unit.item.displayName,
                        label: unit.item.label,
                        categoryName: plan.categoryName,
                        scriptID: plan.scriptID,
                        featureOnMainPage: plan.featureOnMainPage,
                        displayInSelfServiceCategory: plan.displayInSelfServiceCategory,
                        scopeConfig: plan.scope,
                        policyNameTemplate: plan.policyNameTemplate,
                        version: unit.variant.version,
                        overrides: unit.variant.overrides
                    )

                    results.append(await attachIconIfRequested(
                        iconID: plan.iconID,
                        toPolicyID: newPolicyID,
                        itemName: policyName
                    ))
                } catch {
                    results.append(OperationResult(
                        itemName: policyName,
                        success: false,
                        error: failureReason(for: error)
                    ))
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await MainActor.run {
                isCreatingPolicies = false
                deploymentResults = results
                
                let successCount = results.filter(\.success).count
                let failCount = results.count - successCount
                
                if failCount == 0 {
                    creationStatus = "Completed: \(successCount) created"
                    selection.removeAll()
                    lastSelectedID = nil
                } else {
                    creationStatus = "Completed: \(successCount) created, \(failCount) failed"
                }
                
                showResultsSheet = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if !isCreatingPolicies {
                        creationStatus = ""
                    }
                }
            }
            
            await loadData()
        }
    }

    /// Attaches the run's chosen icon to a policy that has just been created, and turns the outcome
    /// into that item's result row.
    ///
    /// The icon was uploaded once, before the batch started, so this is a single extra write per
    /// policy inside the existing throttled loop. A failure here is reported honestly and never
    /// claimed as a clean success — the policy exists, only the icon is missing — following the
    /// convention `clonePolicy` already uses for a failed follow-up write.
    private func attachIconIfRequested(iconID: Int?, toPolicyID policyID: Int?, itemName: String) async -> OperationResult {
        guard let iconID else {
            return OperationResult(itemName: itemName, success: true, error: nil)
        }

        guard let policyID else {
            return OperationResult(
                itemName: itemName,
                success: false,
                error: "Policy created, but Jamf did not return its id, so the Self Service icon could not be attached. Set the icon on the policy in Jamf."
            )
        }

        do {
            try await api.assignPolicyIcon(policyID: policyID, iconID: iconID)
            return OperationResult(itemName: itemName, success: true, error: nil)
        } catch {
            return OperationResult(
                itemName: itemName,
                success: false,
                error: "Policy created (ID \(policyID)), but the Self Service icon could not be attached — this needs the 'Update Policies' privilege. Set the icon on the policy in Jamf."
            )
        }
    }

    /// A reason the administrator can act on, for the per-item row in `OperationResultView`.
    /// `PolicyCreationError` already carries the actionable copy; anything else is reported
    /// plainly rather than leaking framework internals into the results sheet.
    private func failureReason(for error: Error) -> String {
        if let creationError = error as? JamfAPIService.PolicyCreationError {
            return creationError.errorDescription ?? "Jamf rejected this item."
        }
        if let urlError = error as? URLError {
            return "Could not reach Jamf: \(urlError.localizedDescription)"
        }
        return "Creation failed for an unexpected reason. Check this item in Jamf before retrying."
    }
}

// MARK: - Collapsible Section

struct CollapsiblePackageSection: View {
    let sectionTitle: String
    let groupMode: PackageGroupMode
    let items: [InstallomatorItem]
    @Binding var selectedIDs: Set<String>
    var onToggle: (String) -> Void
    var onInspect: (Int) -> Void
    var onExplain: (InstallomatorItem) -> Void
    
    @State private var isExpanded = true
    
    var selectableItems: [InstallomatorItem] {
        items.filter { !$0.isDeployed }
    }
    
    var allSelectableSelected: Bool {
        !selectableItems.isEmpty && selectableItems.allSatisfy { selectedIDs.contains($0.id) }
    }
    
    func toggleGroup() {
        if allSelectableSelected {
            for item in selectableItems { selectedIDs.remove(item.id) }
        } else {
            for item in selectableItems { selectedIDs.insert(item.id) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        // Icon varies by group mode
                        if groupMode == .category {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            Text(sectionTitle)
                                .font(.headline)
                                .foregroundColor(.primary)
                        } else {
                            Text(sectionTitle)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .frame(width: 28)
                        }
                        
                        Text("\(items.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if !selectableItems.isEmpty {
                    Button(action: toggleGroup) {
                        Text(allSelectableSelected ? "Deselect All" : "Select All")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(10)
            
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        PackageCardView(
                            item: item,
                            isSelected: selectedIDs.contains(item.id)
                        )
                        .onTapGesture {
                            onToggle(item.id)
                        }
                        .contextMenu {
                            if item.isDeployed, let policyID = item.policyID {
                                Button {
                                    onInspect(policyID)
                                } label: {
                                    Label("Inspect Policy", systemImage: "magnifyingglass")
                                }
                                Divider()
                            }
                            Button {
                                onExplain(item)
                            } label: {
                                Label("Explain This Label…", systemImage: "questionmark.circle")
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedIDs.contains(item.id) ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }
}
