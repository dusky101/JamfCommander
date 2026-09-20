//
//  PackagesDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI
import Combine

struct PackagesDashboardView: View {
    @ObservedObject var api: JamfAPIService
    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared
    @ObservedObject private var deployment = DeploymentPresenter.shared
    @Environment(\.openWindow) private var openWindow

    /// The Installomator script last deployed with, remembered so a policy running it is recognised
    /// as an Installomator deployment even when the script isn't named "Installomator".
    @AppStorage("installomatorScriptID") private var lastUsedScriptID = ""

    /// Named in the removal confirmation, so it is never ambiguous which tenant is being written to.
    @AppStorage("jamfInstanceURL") private var instanceURL = ""

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

    /// The deployed row whose policy is being edited (see `PackageEditSheet`).
    @State private var editingItem: InstallomatorItem?

    /// The labels Installomator currently publishes, kept from the last load so the editor can say
    /// when a label has been withdrawn. Empty when the list could not be read.
    @State private var upstreamLabels: Set<String> = []
    
    // Deployment, removal & editing
    @State private var isCreatingPolicies = false
    @State private var isRemovingPolicies = false
    @State private var isUpdatingPolicies = false
    @State private var statusMessage = ""
    @State private var showResultsSheet = false
    @State private var operationResults: [OperationResult] = []
    /// The results sheet serves both flows, so it is told which one it is reporting.
    @State private var resultsTitle = "Deployment Results"
    /// Confirmation for removal — deletes are permanent and hit the live tenant.
    @State private var confirmation: ConfirmationData?
    
    // MARK: - Computed Properties
    
    var filteredItems: [InstallomatorItem] {
        let modeFiltered: [InstallomatorItem]
        switch viewMode {
        case .deployed:
            modeFiltered = allItems.filter { $0.isDeployed }
        case .missing:
            modeFiltered = allItems.filter { $0.isMissingLabel }
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

    /// Selected rows that are backed by a real Jamf policy — what "Remove from Jamf" acts on.
    var selectedDeployedItems: [InstallomatorItem] {
        allItems.filter { selection.contains($0.id) && $0.isDeployed }
    }

    /// Any flow is writing to Jamf, so every action stays disabled until it finishes.
    var isBusy: Bool { isCreatingPolicies || isRemovingPolicies || isUpdatingPolicies }

    /// What the footer's two buttons will act on. One selection feeds both actions, so the counts are
    /// spelled out rather than left to be inferred from a single number.
    private var selectionSummary: String {
        var parts: [String] = []
        let available = selectedAvailableItems.count
        let deployed = selectedDeployedItems.count
        if available > 0 {
            parts.append("\(available) available \(available == 1 ? "label" : "labels")")
        }
        if deployed > 0 {
            parts.append("\(deployed) deployed \(deployed == 1 ? "policy" : "policies")")
        }
        guard !parts.isEmpty else { return "Nothing selected" }
        return parts.formatted(.list(type: .and)) + " selected"
    }
    
    var deployedCount: Int { allItems.filter { $0.isDeployed }.count }
    var availableCount: Int { allItems.filter { !$0.isDeployed }.count }

    /// Deployed policies whose Installomator label no longer exists upstream.
    var missingCount: Int { allItems.filter { $0.isMissingLabel }.count }
    
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
                if filteredItems.isEmpty {
                    noMatchesView
                } else {
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
                                    },
                                    onRemove: { item in
                                        requestRemoval(of: [item])
                                    },
                                    onEdit: { item in
                                        editingItem = item
                                    }
                                )
                            }
                        }
                        .padding()
                        .padding(.bottom, 60)
                    }
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
            // Each icon attach is a Classic write, so a batch bumps the refresh token too, and so
            // does every delete. Skip the bump while we're mid-write or already reloading — both
            // flows reload themselves afterwards, and a duplicate full scan would compete for Jamf's
            // rate limit.
            guard !isBusy, !isLoading else { return }
            Task { await loadData() }
        }
        // The deployment window hands back a plan; the deploying still happens here, exactly as it
        // did when this was a sheet. `onReceive` rather than `onChange` because a plan is not
        // `Equatable` and does not need to be — this only cares that one arrived.
        .onReceive(deployment.$completedPlan.compactMap { $0 }) { plan in
            deployment.completedPlan = nil
            deployPolicies(plan: plan)
        }
        .sheet(isPresented: $showResultsSheet) {
            OperationResultView(
                title: resultsTitle,
                results: operationResults,
                onDismiss: {
                    showResultsSheet = false
                    operationResults = []
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
        .sheet(item: $editingItem) { item in
            PackageEditSheet(
                api: api,
                item: item,
                siblings: siblingPolicies(of: item),
                upstreamLabels: upstreamLabels,
                onApply: { jobs in
                    editingItem = nil
                    applyEdits(jobs)
                },
                onCancel: { editingItem = nil }
            )
        }
        .commanderConfirmation(data: $confirmation)
    }
    
    // MARK: - Header
    
    /// Title on the left, controls on the right — until there is not room, and then the title goes
    /// above them.
    ///
    /// **Measured, not estimated** (`START_HERE.md` §4 says so, and the numbers here were taken with
    /// `NSFont.preferredFont(forTextStyle: .title2)` in bold):
    ///
    /// | | width |
    /// | --- | --- |
    /// | "Installomator Manager", one line | **184.0pt** |
    /// | "Installomator", the longer of the two words | **108.4pt** |
    /// | group picker · view picker · Refresh · three 16pt gaps · 16pt padding either side | 726.5pt |
    ///
    /// So the row needs **910.5pt** on one line and **838.5pt** on two — the first figure being
    /// exactly the one `START_HERE.md` records. Under that, nothing shrinks gracefully: `Text` has
    /// no minimum and will happily compress to one character per line, which is what turned the
    /// title into "In-stal-lo-ma-tor Man-ager".
    ///
    /// `ViewThatFits` picks the first of the three that fits, so the degradation is title on one
    /// line → title on two → title on its own row above the controls. Two lines beside the controls
    /// is the shape the maintainer confirmed reads well; below that the controls keep their width
    /// and the title takes the space it needs.
    var headerView: some View {
        ViewThatFits(in: .horizontal) {
            // 1. Everything on one line.
            HStack(spacing: 16) {
                headerTitle
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                headerControls
            }

            // 2. The title wrapped to two lines, controls still beside it. 112 rather than 108.4 so
            //    the longer word is not sitting flush against its own bounds.
            HStack(spacing: 16) {
                headerTitle
                    .frame(width: 112, alignment: .leading)
                Spacer(minLength: 0)
                headerControls
            }

            // 3. Too narrow for both: the title takes its own row.
            VStack(alignment: .leading, spacing: 12) {
                headerTitle
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerControls
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Two lines at most, wherever it ends up. Past that the row grows taller instead of the text
    /// getting smaller, and a header that pushes the list down the window is its own problem.
    private var headerTitle: some View {
        Text("Installomator Manager")
            .font(.title2)
            .fontWeight(.bold)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var headerControls: some View {
        if !allItems.isEmpty {
            HStack(spacing: 16) {
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
                    Text("Missing (\(missingCount))").tag(PackageViewMode.missing)
                    Text("Available (\(availableCount))").tag(PackageViewMode.available)
                    Text("All (\(allItems.count))").tag(PackageViewMode.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 420)
                .help("Missing lists deployed policies whose Installomator label is no longer published upstream.")
                .onChange(of: viewMode) {
                    selection.removeAll()
                    lastSelectedID = nil
                }

                Button(action: {
                    Task { await loadData(bypassingCache: true) }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
        }
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
    
    /// The module has data, but nothing passes the current view mode and search. Most often this is
    /// the Missing view with nothing missing — which is good news, and should say so rather than
    /// leaving a blank panel.
    var noMatchesView: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty && viewMode == .missing ? "checkmark.seal" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(searchText.isEmpty && viewMode == .missing ? .green : .secondary)
            Text(noMatchesTitle)
                .font(.title3)
                .fontWeight(.medium)
            Text(noMatchesDetail)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !searchText.isEmpty {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var noMatchesTitle: String {
        if !searchText.isEmpty { return "No matches" }
        switch viewMode {
        case .missing: return "Nothing missing"
        case .deployed: return "No deployed policies"
        case .available: return "No available labels"
        case .all: return "No labels"
        }
    }

    private var noMatchesDetail: String {
        if !searchText.isEmpty {
            return "No application name or Installomator label matches “\(searchText)”."
        }
        switch viewMode {
        case .missing:
            return "Every deployed policy uses a label that Installomator still publishes."
        case .deployed:
            return "No policy in Jamf runs an Installomator script with a label in parameter 4."
        case .available:
            return "Every upstream label already has a policy in Jamf."
        case .all:
            return "No labels were loaded."
        }
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
            HStack(spacing: 12) {
                Text(selectionSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(statusMessage.contains("Error") || statusMessage.contains("failed") ? .red : .green)
                }

                // Both actions appear only once a deployed row is selected — they change or delete
                // real policies, so neither should sit there inviting a click while nothing is at
                // stake. Editing is one policy at a time: the sheet prefills from that policy's own
                // payload and writes only what changed, which has no meaning for a mixed selection.
                if !selectedDeployedItems.isEmpty {
                    Button {
                        editingItem = selectedDeployedItems.first
                    } label: {
                        Label("Edit…", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || selectedDeployedItems.count != 1)
                    .help(selectedDeployedItems.count == 1
                          ? "Edit this policy's name, category, Self Service options, scope, label and overrides."
                          : "Select a single deployed policy to edit it.")

                    Button(role: .destructive) {
                        requestRemoval(of: selectedDeployedItems)
                    } label: {
                        if isRemovingPolicies {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Remove from Jamf…", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isBusy)
                    .help("Deletes the selected install policies from Jamf and Self Service. Applications already installed on a Mac are left alone.")
                }
                
                Button(action: {
                    DeploymentPresenter.shared.begin(with: selectedAvailableItems, api: api)
                    openWindow(id: DeploymentWindowID)
                }) {
                    if isCreatingPolicies {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add to Jamf")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || selectedAvailableItems.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    // MARK: - Data Loading
    
    /// - Parameter bypassingCache: `true` re-reads the labels and every policy from Jamf. Passed by
    ///   Refresh only.
    func loadData(bypassingCache: Bool = false) async {
        isLoading = true
        loadError = nil
        selection.removeAll()
        lastSelectedID = nil
        
        do {
            async let labelsResult = api.fetchInstallomatorLabelsFromGitHub(bypassingCache: bypassingCache)
            async let scriptIDsResult = api.fetchInstallomatorScriptIDs(bypassingCache: bypassingCache)

            // Script ids widen detection beyond "the policy's script is called Installomator".
            // A failure here only narrows detection, so it degrades rather than failing the load.
            var knownScriptIDs = (try? await scriptIDsResult) ?? []
            if !lastUsedScriptID.isEmpty {
                knownScriptIDs.insert(lastUsedScriptID)
            }

            let scan = try await api.fetchInstallomatorPolicies(knownScriptIDs: knownScriptIDs,
                                                                bypassingCache: bypassingCache)
            let allLabels = try await labelsResult

            let deployed = scan.deployed
            let deployedLabels = Set(deployed.map { $0.label.lowercased() })

            // What upstream still publishes. An empty list can only mean the fetch came back with
            // nothing usable, so every deployed row is treated as current rather than marking the
            // whole estate missing on the strength of a bad read.
            let publishedLabels = Set(allLabels.map { $0.lowercased() })
            let upstreamListIsUsable = !publishedLabels.isEmpty

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
                    existingPolicyName: nil,
                    labelExistsUpstream: !upstreamListIsUsable || publishedLabels.contains(info.label.lowercased())
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
                        existingPolicyName: existingPolicyName,
                        // Available rows come from the upstream list, so the label exists by definition.
                        labelExistsUpstream: true
                    ))
                }
            }

            items.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            let possiblyDeployedCount = items.filter(\.isPossiblyDeployed).count
            let missingLabelCount = items.filter(\.isMissingLabel).count
            print("[Installomator] Loaded \(items.count) items (\(deployed.count) deployed, \(items.count - deployed.count) available, \(possiblyDeployedCount) possibly deployed, \(missingLabelCount) missing upstream)")

            await MainActor.run {
                allItems = items
                upstreamLabels = publishedLabels
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
    
    /// Every row is selectable: available rows feed "Add to Jamf", deployed rows feed
    /// "Remove from Jamf". Each action reads only the subset it applies to, so a mixed selection is
    /// safe — selecting a deployed row can never deploy it, and vice versa.
    func toggleSelection(id: String) {
        guard allItems.contains(where: { $0.id == id }) else { return }
        
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        if isShiftPressed, let lastId = lastSelectedID {
            let allVisibleItems = filteredItems
            
            if let lastIndex = allVisibleItems.firstIndex(where: { $0.id == lastId }),
               let currentIndex = allVisibleItems.firstIndex(where: { $0.id == id }) {
                
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                
                selection.formUnion(allVisibleItems[start...end].map(\.id))
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
        statusMessage = "Initialising..."
        operationResults = []

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
                    statusMessage = "Deploying \(index + 1) of \(work.count)..."
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
                resultsTitle = "Deployment Results"
                operationResults = results
                
                let successCount = results.filter(\.success).count
                let failCount = results.count - successCount
                
                if failCount == 0 {
                    statusMessage = "Completed: \(successCount) created"
                    selection.removeAll()
                    lastSelectedID = nil
                } else {
                    statusMessage = "Completed: \(successCount) created, \(failCount) failed"
                }
                
                showResultsSheet = true
                
                clearStatusMessageShortly()
            }
            
            await loadData()
        }
    }

    // MARK: - Removal

    /// Asks before deleting, stating exactly which policies go, from which tenant, and — just as
    /// importantly — what deleting them does *not* do. Deletion is permanent and reaches production
    /// (root `CLAUDE.md`, invariant 1).
    private func requestRemoval(of items: [InstallomatorItem]) {
        let targets = removalTargets(for: items)
        guard !targets.isEmpty else { return }

        let count = targets.count
        let noun = count == 1 ? "policy" : "policies"
        let instance = instanceURL.isEmpty ? "your Jamf instance" : instanceURL

        let message = """
        \(count) Installomator install \(noun) will be deleted from \(instance):

        \(summarise(targets.map(\.policyName)))

        This removes the \(noun) from Jamf and from Self Service. It does not uninstall the application from any Mac. Deleted policies cannot be restored.
        """

        confirmation = ConfirmationData(
            title: "Delete \(count) \(noun)?",
            message: message,
            actionTitle: "Delete \(count) \(noun.capitalized)",
            role: .destructive,
            action: { performRemoval(of: targets) }
        )
    }

    /// The Jamf policies behind the given rows. A row with no policy id cannot be deleted, so it is
    /// dropped here rather than turned into a request with nothing to target.
    private func removalTargets(for items: [InstallomatorItem]) -> [JamfAPIService.InstallomatorPolicyTarget] {
        items.compactMap { item in
            guard item.isDeployed, let policyID = item.policyID else { return nil }
            return JamfAPIService.InstallomatorPolicyTarget(
                policyID: policyID,
                policyName: item.policyName ?? item.displayName,
                label: item.label
            )
        }
    }

    /// Runs the confirmed deletion through the throttled service method and reports what actually
    /// happened, per policy. The selection survives a partial failure so the failed rows can be
    /// retried without hunting for them again.
    private func performRemoval(of targets: [JamfAPIService.InstallomatorPolicyTarget]) {
        guard !targets.isEmpty else { return }

        isRemovingPolicies = true
        statusMessage = "Removing \(targets.count) \(targets.count == 1 ? "policy" : "policies")..."
        operationResults = []

        Task {
            let results = await api.deleteInstallomatorPolicies(targets)

            await MainActor.run {
                isRemovingPolicies = false
                resultsTitle = "Removal Results"
                operationResults = results

                let successCount = results.filter(\.success).count
                let failCount = results.count - successCount

                if failCount == 0 {
                    statusMessage = "Completed: \(successCount) removed"
                    selection.removeAll()
                    lastSelectedID = nil
                } else {
                    statusMessage = "Completed: \(successCount) removed, \(failCount) failed"
                }

                showResultsSheet = true
                clearStatusMessageShortly()
            }

            await loadData()
        }
    }

    // MARK: - Editing

    /// The other deployed policies that run the same label — what "apply to the other policies using
    /// this label" acts on. Matched case-insensitively, because a label typed into Jamf by hand can
    /// differ in case from the upstream one.
    private func siblingPolicies(of item: InstallomatorItem) -> [InstallomatorItem] {
        allItems.filter {
            $0.isDeployed
                && $0.id != item.id
                && $0.label.caseInsensitiveCompare(item.label) == .orderedSame
        }
    }

    /// Writes the edits the sheet confirmed, then reloads so the rows show what Jamf now holds.
    /// Results are per policy — a sibling that Jamf refused is never hidden behind the primary
    /// policy's success.
    private func applyEdits(_ jobs: [JamfAPIService.InstallomatorPolicyEditJob]) {
        guard !jobs.isEmpty else { return }

        isUpdatingPolicies = true
        statusMessage = "Updating \(jobs.count) \(jobs.count == 1 ? "policy" : "policies")..."
        operationResults = []

        Task {
            let results = await api.applyInstallomatorPolicyEdits(jobs)

            await MainActor.run {
                isUpdatingPolicies = false
                resultsTitle = "Update Results"
                operationResults = results

                let successCount = results.filter(\.success).count
                let failCount = results.count - successCount

                statusMessage = failCount == 0
                    ? "Completed: \(successCount) updated"
                    : "Completed: \(successCount) updated, \(failCount) failed"

                showResultsSheet = true
                clearStatusMessageShortly()
            }

            await loadData()
        }
    }

    // MARK: - Shared helpers

    /// Clears the footer's status line once it has been read, unless another write has started.
    private func clearStatusMessageShortly() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if !isBusy { statusMessage = "" }
        }
    }

    /// "A, B and 3 more" — keeps a long list readable inside a confirmation dialog.
    private func summarise(_ names: [String], showing limit: Int = 5) -> String {
        guard names.count > limit else { return names.formatted(.list(type: .and)) }
        return "\(names.prefix(limit).formatted(.list(type: .and))) and \(names.count - limit) more"
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
    var onRemove: (InstallomatorItem) -> Void
    var onEdit: (InstallomatorItem) -> Void
    
    @State private var isExpanded = true
    
    /// Every row in the section counts — available rows for deployment, deployed rows for removal —
    /// so "Select All" in the Missing view selects exactly the policies that need clearing out.
    var allSelected: Bool {
        !items.isEmpty && items.allSatisfy { selectedIDs.contains($0.id) }
    }
    
    func toggleGroup() {
        if allSelected {
            for item in items { selectedIDs.remove(item.id) }
        } else {
            for item in items { selectedIDs.insert(item.id) }
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
                
                if !items.isEmpty {
                    Button(action: toggleGroup) {
                        Text(allSelected ? "Deselect All" : "Select All")
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
                                Button {
                                    onEdit(item)
                                } label: {
                                    Label("Edit Package…", systemImage: "slider.horizontal.3")
                                }
                                Divider()
                            }
                            Button {
                                onExplain(item)
                            } label: {
                                Label("Explain This Label…", systemImage: "questionmark.circle")
                            }
                            if item.isDeployed {
                                Divider()
                                Button(role: .destructive) {
                                    onRemove(item)
                                } label: {
                                    Label("Remove from Jamf…", systemImage: "trash")
                                }
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedIDs.contains(item.id) ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                        // The whole card is the selection control, so expose it as one element
                        // rather than as a row of unlabelled badges beside a tick.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(selectedIDs.contains(item.id) ? [.isButton, .isSelected] : .isButton)
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
