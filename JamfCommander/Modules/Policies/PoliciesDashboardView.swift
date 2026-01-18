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
            if !selectedPolicyIDs.isEmpty {
                // Action Panel (Policies Mode)
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
                .background(Color(nsColor: .controlBackgroundColor))
                .zIndex(2)
            } else {
                // Filter Bar
                FilterBar(
                    searchText: $searchText,
                    categories: categories,
                    selectedCategory: $selectedCategory,
                    policies: policies // Pass policies for counts
                ) {
                    Task { await loadData() }
                }
                .zIndex(1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // --- Content ---
            if isLoading {
                ProgressView("Loading Policies...").frame(maxHeight: .infinity)
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
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: selectedPolicyIDs.isEmpty)
        .task { await loadData() }
        .sheet(item: $inspectorSelection) { selection in
            PoliciesInspectorView(policyId: selection.id, api: api)
        }
    }
    
    // MARK: - Actions
    
    func loadData() async {
        do {
            async let fetchedPolicies = api.fetchPolicies()
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
                try await api.movePolicy(id: id, toCategoryID: targetCatId) // Ensure label 'id:' and 'toCategoryID:' are used
                await loadData()
            } catch {
                print("Failed to move policy: \(error)")
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
