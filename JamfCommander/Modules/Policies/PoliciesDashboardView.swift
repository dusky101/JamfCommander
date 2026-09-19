//
//  PoliciesDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI
import AppKit

struct PoliciesDashboardView: View {
    @ObservedObject var api: JamfAPIService
    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared
    /// Observed only for the "read at" stamp — the list itself is `@State`, fetched below.
    @ObservedObject private var cache = SessionCache.shared

    // Data
    @State private var policies: [Policy] = []
    @State private var categories: [Category] = []
    
    // Selection
    @State private var selectedPolicyIDs = Set<Int>()
    @State private var lastSelectedID: Int?
    
    // Filter
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    
    // States
    @State private var isLoading = true
    @State private var inspectorSelection: InspectorSelection?
    @State private var isBusy = false
    @State private var actionStatus = ""
    @State private var showExportProgress = false
    @StateObject private var exportProgress = ExportProgress()
    
    // MARK: - Logic
    var filteredPolicies: [Policy] {
        policies.filter { policy in
            let matchesText = searchText.isEmpty ||
                              policy.name.localizedCaseInsensitiveContains(searchText) ||
                              String(policy.id).contains(searchText)
            let matchesCategory = (selectedCategory == nil) || (policy.categoryName == selectedCategory?.name)
            return matchesText && matchesCategory
        }
    }
    
    var groupedPolicies: [(key: String, value: [Policy])] {
        let grouped = Dictionary(grouping: filteredPolicies) { $0.safeCategory }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Top Bar ---
            if selectedPolicyIDs.count == 1,
               let singlePolicy = policies.first(where: { $0.id == selectedPolicyIDs.first }) {
                // Single-item Action Bar (singular wording; Edit opens the inspector)
                SingleActionBar(
                    api: api,
                    policy: singlePolicy,
                    categories: categories,
                    isBusy: $isBusy,
                    statusMessage: $actionStatus,
                    onEdit: { id in inspectorSelection = InspectorSelection(id: id) },
                    onClearSelection: { withAnimation { selectedPolicyIDs.removeAll() } },
                    onRefresh: { await loadData() }
                )
                .frame(height: 180)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            } else if !selectedPolicyIDs.isEmpty {
                // Action Panel (Policies Mode — bulk, 2+ selected)
                ActionPanelView(
                    api: api,
                    mode: .policies,
                    categories: categories,
                    policies: policies,
                    selectedIDs: $selectedPolicyIDs,
                    isBusy: $isBusy,
                    statusMessage: $actionStatus,
                    onRefresh: { await loadData() }
                )
                .frame(height: 180)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            } else {
                // Filter Bar
                FilterBar(
                    searchText: $searchText,
                    categories: categories,
                    selectedCategory: $selectedCategory,
                    policies: policies, // Pass policies for counts
                    onRefresh: {
                        // Refresh always goes to Jamf. Without that there is no way to pick up a
                        // change made in the Jamf console by somebody else.
                        Task { await loadData(bypassingCache: true) }
                    },
                    onExport: {
                        exportPolicies()
                    },
                    readAt: cache.readAt[.policies]
                )
                .zIndex(1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // --- Content ---
            if isLoading {
                ProgressView("Loading Policies...").frame(maxHeight: .infinity)
            } else if groupedPolicies.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedPolicies, id: \.key) { group in
                            CollapsiblePolicySection(
                                title: group.key,
                                policies: group.value,
                                categories: categories,
                                selectedIDs: $selectedPolicyIDs,
                                onInspect: { id in inspectorSelection = InspectorSelection(id: id) },
                                onDelete: { id in deletePolicy(id: id) },
                                onMove: { id, targetCatId in movePolicy(id: id, targetCatId: targetCatId) },
                                onToggle: { id in toggleSelection(for: id) }
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 50)
                }
            }
        }
        // Pin to the top. Without this, content taller than the pane is centred, so the overflow is
        // split above and below and the filter bar disappears under the title bar instead of simply
        // running off the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: selectedPolicyIDs.isEmpty)
        .task { await loadData() }
        .onChange(of: refreshCoordinator.token) { Task { await loadData() } }
        .sheet(item: $inspectorSelection) { selection in
            PoliciesInspectorView(policyId: selection.id, api: api)
        }
        .sheet(isPresented: $showExportProgress) {
            ExportProgressSheet(isPresented: $showExportProgress, progress: exportProgress, types: [.policies])
        }
    }
    
    /// Nothing to show. Told apart so the message can say which it is: an empty tenant and a search
    /// that matched nothing look identical otherwise, and only one of them is fixed by clearing the
    /// search. Inside a ScrollView so the text can never demand height and push the module around.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: policies.isEmpty ? "scroll" : "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)

                Text(policies.isEmpty ? "No policies in this instance" : "No matches")
                    .font(.headline)

                Text(emptyDetail)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !searchText.isEmpty || selectedCategory != nil {
                    Button("Clear Filters") {
                        searchText = ""
                        selectedCategory = nil
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetail: String {
        if policies.isEmpty {
            return "This Jamf instance has no policies, or none this API client may read."
        }
        if !searchText.isEmpty, let selectedCategory {
            return "No policy in \(selectedCategory.name) matches “\(searchText)”."
        }
        if !searchText.isEmpty {
            return "No policy matches “\(searchText)”."
        }
        if let selectedCategory {
            return "No policy is filed under \(selectedCategory.name)."
        }
        return "Nothing matches the current filters."
    }

    // MARK: - Actions
    
    /// - Parameter bypassingCache: `true` reads from Jamf regardless of what this session has
    ///   already read. Passed by Refresh; left `false` when the module is simply opened again, which
    ///   is the case the cache exists for.
    func loadData(bypassingCache: Bool = false) async {
        do {
            async let fetchedPolicies = api.fetchPolicies(bypassingCache: bypassingCache)
            async let fetchedCategories = api.fetchCategories()
            let (p, c) = try await (fetchedPolicies, fetchedCategories)
            await MainActor.run {
                self.policies = p
                self.categories = c
                self.isLoading = false
            }
        } catch {
            print("Error: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    private func deletePolicy(id: Int) {
        Task {
            try? await api.deletePolicy(id: id)
            if selectedPolicyIDs.contains(id) { selectedPolicyIDs.remove(id) }
            await loadData()
        }
    }
    
    private func movePolicy(id: Int, targetCatId: Int) {
        Task {
            do {
                let targetName = categories.first(where: { $0.id == targetCatId })?.name ?? ""
                try await api.movePolicy(id: id, toCategoryID: targetCatId, categoryName: targetName)
                await loadData()
            } catch {
                print("Failed to move policy: \(error)")
            }
        }
    }
    
    private func exportPolicies() {
        exportProgress.reset()
        showExportProgress = true
        
        Task {
            let csvContent = await ExportService.exportPoliciesDetailedToCSV(policies: policies, api: api, progress: exportProgress)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = dateFormatter.string(from: Date())
            
            // Mark complete and wait a moment for UI to update
            exportProgress.markComplete()
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second to show completion
            
            await MainActor.run {
                showExportProgress = false
                _ = ExportService.saveCSVToFile(content: csvContent, defaultName: "Policies_\(dateString).csv")
            }
        }
    }
    
    // MARK: - Shift-Click Selection
    func toggleSelection(for id: Int) {
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        if isShiftPressed, let lastId = lastSelectedID {
            let allVisible = groupedPolicies.flatMap { $0.value }
            
            if let lastIndex = allVisible.firstIndex(where: { $0.id == lastId }),
               let currentIndex = allVisible.firstIndex(where: { $0.id == id }) {
                
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                
                let idsToSelect = allVisible[start...end].map { $0.id }
                selectedPolicyIDs.formUnion(idsToSelect)
            }
        } else {
            if selectedPolicyIDs.contains(id) {
                selectedPolicyIDs.remove(id)
            } else {
                selectedPolicyIDs.insert(id)
            }
            lastSelectedID = id
        }
    }
}

// Local Section
struct CollapsiblePolicySection: View {
    let title: String
    let policies: [Policy]
    let categories: [Category]
    @Binding var selectedIDs: Set<Int>
    
    var onInspect: (Int) -> Void
    var onDelete: (Int) -> Void
    var onMove: (Int, Int) -> Void
    var onToggle: (Int) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "folder.fill").foregroundColor(.purple)
                    Text(title).font(.headline).foregroundColor(.primary)
                    Spacer()
                    Text("\(policies.count)").font(.caption).foregroundColor(.secondary)
                    Image(systemName: "chevron.right").foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(policies) { policy in
                        PolicyCardView(policy: policy, categoryName: title)
                            .onTapGesture { onToggle(policy.id) }
                            .contextMenu {
                                // 1. Inspect
                                if selectedIDs.count <= 1 || !selectedIDs.contains(policy.id) {
                                    Button("Inspect") { onInspect(policy.id) }
                                }
                                
                                // 2. Move
                                Menu("Move to...") {
                                    ForEach(categories) { cat in
                                        Button(cat.name) { onMove(policy.id, cat.id) }
                                    }
                                }
                                
                                Divider()
                                
                                // 3. Delete
                                Button("Delete", role: .destructive) { onDelete(policy.id) }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedIDs.contains(policy.id) ? Color.purple : Color.clear, lineWidth: 2)
                            )
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }
}
