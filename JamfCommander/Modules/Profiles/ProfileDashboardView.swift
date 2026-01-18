//
//  ProfileDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI
import AppKit // Required for detecting Shift key (NSEvent)

struct ProfileDashboardView: View {
    let profiles: [ConfigProfile]
    let categories: [Category]
    @ObservedObject var api: JamfAPIService
    
    // Filter State
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @Binding var selectedProfileIDs: Set<ConfigProfile.ID>
    
    // New: Refresh Capability (Restored)
    var refreshAction: () async -> Void
    
    // Selection Logic State
    @State private var lastSelectedID: Int? // Tracks the last clicked item for Shift-Select ranges
    
    // Action State
    @State private var inspectorSelection: InspectorSelection?
    @State private var isBusy = false
    @State private var actionStatus = ""
    
    // MARK: - Filtering & Grouping Logic
    
    var filteredProfiles: [ConfigProfile] {
        profiles.filter { profile in
            // 1. Text Filter
            let matchesText = searchText.isEmpty ||
                              profile.name.localizedCaseInsensitiveContains(searchText) ||
                              String(profile.id).contains(searchText)
            
            // 2. Category Filter
            let matchesCategory = (selectedCategory == nil) || (profile.categoryName == selectedCategory?.name)
            
            return matchesText && matchesCategory
        }
    }
    
    var groupedProfiles: [(key: String, value: [ConfigProfile])] {
        let grouped = Dictionary(grouping: filteredProfiles) { $0.categoryName }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Top Bar (Switches between Filter and Actions) ---
            if !selectedProfileIDs.isEmpty {
                // Show Action Panel when items are selected
                ActionPanelView(
                    api: api,
                    mode: .profiles, // Add this
                    categories: categories,
                    profiles: profiles,
                    selectedIDs: $selectedProfileIDs, // Rename this argument
                    isBusy: $isBusy,
                    statusMessage: $actionStatus,
                    onRefresh: {
                        await refreshAction() // <--- Restored Refresh Call
                    }
                )
                .frame(height: 180)
                .transition(.move(edge: .top).combined(with: .opacity))
                .background(Color(nsColor: .controlBackgroundColor))
                .zIndex(2)
            } else {
                // Show Filter Bar normally
                FilterBar(
                    searchText: $searchText,
                    categories: categories,
                    selectedCategory: $selectedCategory,
                    profiles: profiles
                )
                .zIndex(1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // --- Main List Area ---
            ScrollView {
                LazyVStack(spacing: 20) {
                    if filteredProfiles.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 50)
                    } else {
                        ForEach(groupedProfiles, id: \.key) { group in
                            CollapsibleCategorySection(
                                title: group.key,
                                profiles: group.value,
                                categories: categories,
                                selectedProfileIDs: $selectedProfileIDs,
                                onInspect: { id in
                                    inspectorSelection = InspectorSelection(id: id)
                                },
                                onDelete: { id in
                                    deleteProfile(id: id)
                                },
                                onMove: { id, targetCatId in
                                    moveProfile(id: id, targetCatId: targetCatId)
                                },
                                onToggleSelection: { id in
                                    toggleSelection(for: id)
                                }
                            )
                        }
                    }
                }
                .padding()
                .padding(.bottom, 50)
            }
        }
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: selectedProfileIDs.isEmpty)
        .sheet(item: $inspectorSelection) { selection in
            ProfileInspectorView(profileId: selection.id, api: api)
        }
    }
    
    // MARK: - Actions
    
    private func deleteProfile(id: Int) {
        Task {
            try? await api.deleteProfile(id: id)
            if selectedProfileIDs.contains(id) {
                selectedProfileIDs.remove(id)
            }
            await refreshAction() // Refresh after single delete
        }
    }
    
    private func moveProfile(id: Int, targetCatId: Int) {
        Task {
            do {
                try await api.moveProfile(id, toCategoryID: targetCatId)
                print("Moved profile \(id) to category \(targetCatId)")
                await refreshAction() // Refresh after single move
            } catch {
                print("Failed to move profile: \(error)")
            }
        }
    }
    
    // MARK: - Smart Selection Logic (Shift-Click)
    private func toggleSelection(for id: Int) {
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        if isShiftPressed, let lastId = lastSelectedID {
            // 1. Flatten the visible list to determine visual order
            let allVisibleProfiles = groupedProfiles.flatMap { $0.value }
            
            // 2. Find indices
            if let lastIndex = allVisibleProfiles.firstIndex(where: { $0.id == lastId }),
               let currentIndex = allVisibleProfiles.firstIndex(where: { $0.id == id }) {
                
                // 3. Select Range
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                
                let idsToSelect = allVisibleProfiles[start...end].map { $0.id }
                selectedProfileIDs.formUnion(idsToSelect)
            }
        } else {
            // Standard Toggle
            if selectedProfileIDs.contains(id) {
                selectedProfileIDs.remove(id)
            } else {
                selectedProfileIDs.insert(id)
            }
            // Update anchor only on a normal click
            lastSelectedID = id
        }
    }
}

// MARK: - Collapsible Section Component
struct CollapsibleCategorySection: View {
    let title: String
    let profiles: [ConfigProfile]
    let categories: [Category]
    @Binding var selectedProfileIDs: Set<ConfigProfile.ID>
    
    var onInspect: (Int) -> Void
    var onDelete: (Int) -> Void
    var onMove: (Int, Int) -> Void
    var onToggleSelection: (Int) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("\(profiles.count) profiles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            // Items
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(profiles) { profile in
                        ProfileCardView(profile: profile, categoryName: title)
                            .onTapGesture {
                                onToggleSelection(profile.id)
                            }
                            .contextMenu {
                                // 1. Inspect
                                if selectedProfileIDs.count <= 1 || !selectedProfileIDs.contains(profile.id) {
                                    Button("Inspect") { onInspect(profile.id) }
                                }
                                
                                // 2. Move
                                Menu("Move to...") {
                                    ForEach(categories) { cat in
                                        Button(cat.name) {
                                            onMove(profile.id, cat.id)
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                // 3. Delete
                                Button("Delete", role: .destructive) { onDelete(profile.id) }
                            }
                            // Selection Styling
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedProfileIDs.contains(profile.id) ? Color.blue : Color.clear, lineWidth: 2)
                            )
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}
