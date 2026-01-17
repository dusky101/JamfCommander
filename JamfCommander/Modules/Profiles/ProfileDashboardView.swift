//
//  ProfileDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ProfileDashboardView: View {
    let profiles: [ConfigProfile]
    let categories: [Category]
    @ObservedObject var api: JamfAPIService
    
    // Filter State
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @Binding var selectedProfileIDs: Set<ConfigProfile.ID>
    
    // Inspector Selection
    @State private var inspectorSelection: InspectorSelection?
    
    // MARK: - Filtering & Grouping Logic
    
    var filteredProfiles: [ConfigProfile] {
        profiles.filter { profile in
            // 1. Text Filter
            let matchesText = searchText.isEmpty ||
                              profile.name.localizedCaseInsensitiveContains(searchText) ||
                              String(profile.id).contains(searchText)
            
            // 2. Category Filter
            // Since api.fetchProfiles() now populates 'categoryName' correctly,
            // we can filter strictly on it.
            let matchesCategory = (selectedCategory == nil) || (profile.categoryName == selectedCategory?.name)
            
            return matchesText && matchesCategory
        }
    }
    
    // Group the filtered profiles by their Category Name for the UI
    var groupedProfiles: [(key: String, value: [ConfigProfile])] {
        let grouped = Dictionary(grouping: filteredProfiles) { $0.categoryName }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Top Filter Bar ---
            FilterBar(
                searchText: $searchText,
                categories: categories,
                selectedCategory: $selectedCategory,
                profiles: profiles // <--- ADD THIS LINE to pass the data for counting
            )
            .zIndex(1)
            
            // --- Main List Area ---
            ScrollView {
                LazyVStack(spacing: 20) {
                    if filteredProfiles.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 50)
                    } else {
                        // Loop through Groups instead of a flat list
                        ForEach(groupedProfiles, id: \.key) { group in
                            CollapsibleCategorySection(
                                title: group.key,
                                profiles: group.value,
                                selectedProfileIDs: $selectedProfileIDs,
                                onInspect: { id in
                                    inspectorSelection = InspectorSelection(id: id)
                                },
                                onDelete: { id in
                                    deleteProfile(id: id)
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
        // Inspector Sheet
        .sheet(item: $inspectorSelection) { selection in
            ProfileInspectorView(profileId: selection.id, api: api)
        }
    }
    
    private func deleteProfile(id: Int) {
        Task {
            try? await api.deleteProfile(id: id)
            if selectedProfileIDs.contains(id) {
                selectedProfileIDs.remove(id)
            }
        }
    }
}

// MARK: - Collapsible Section Component
struct CollapsibleCategorySection: View {
    let title: String
    let profiles: [ConfigProfile]
    @Binding var selectedProfileIDs: Set<ConfigProfile.ID>
    var onInspect: (Int) -> Void
    var onDelete: (Int) -> Void
    
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
                                toggleSelection(for: profile.id)
                            }
                            .contextMenu {
                                Button("Inspect") { onInspect(profile.id) }
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
        // Container Style
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func toggleSelection(for id: Int) {
        if selectedProfileIDs.contains(id) {
            selectedProfileIDs.remove(id)
        } else {
            selectedProfileIDs.insert(id)
        }
    }
}
