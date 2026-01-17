//
//  ProfileTableView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//


import SwiftUI

struct ProfileTableView: View {
    let profiles: [ConfigProfile]
    let categories: [Category] // Passed in for the filter dropdown
    
    @Binding var selectedProfileIDs: Set<ConfigProfile.ID>
    
    // Local Filter State
    @State private var filterText = ""
    @State private var selectedCategoryFilter: Int = -1 // -1 means "All"
    
    // View Details State
    @State private var showInspector = false
    @State private var inspectorProfileID: Int?
    
    // Filter Logic
    var filteredProfiles: [ConfigProfile] {
        profiles.filter { profile in
            let matchesName = filterText.isEmpty || profile.name.localizedCaseInsensitiveContains(filterText)
            // Note: The basic Profile object might not have the category ID attached in the list view depending on API.
            // If the basic list response doesn't include category ID, we can only filter by name for now,
            // OR we fetch full details. For now, let's filter by Name to keep it fast.
            return matchesName
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // TOOLBAR / FILTER BAR
            HStack {
                Text("Configuration Profiles")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .frame(width: 200)
                
                // Refresh Count
                Text("\(filteredProfiles.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial) // Header background
            
            // TABLE
            Table(filteredProfiles, selection: $selectedProfileIDs) {
                TableColumn("ID") { profile in
                    Text(String(profile.id))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .width(min: 50, max: 60)
                
                TableColumn("Name") { profile in
                    HStack {
                        Image(systemName: "doc.text")
                        Text(profile.name)
                            .font(.system(.body, design: .rounded))
                    }
                    .padding(.vertical, 4)
                }
            }
            // Context Menu for "Right Click"
            .contextMenu(forSelectionType: ConfigProfile.ID.self) { selectedIDs in
                if selectedIDs.count == 1, let id = selectedIDs.first {
                    Button("Inspect Profile") {
                        inspectorProfileID = id
                        showInspector = true
                    }
                }
            }
            .scrollContentBackground(.hidden) // Removes the default white/grey table background
        }
        .background(Color.clear) // Let the Liquid Glass show through
        .sheet(isPresented: $showInspector) {
            if let id = inspectorProfileID {
                // You'll need to pass the API service down or EnvironmentObject it.
                // For this modular view, it's cleaner to pass it in init,
                // but let's assume we pass it from ContentView for now.
                EmptyView() // Placeholder: See ContentView for implementation
            }
        }
    }
}
