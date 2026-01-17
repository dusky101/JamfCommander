//
//  ActionPanelView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//


import SwiftUI

struct ActionPanelView: View {
    @ObservedObject var api: JamfAPIService
    
    // Data passed from parent
    let categories: [Category]
    @Binding var selectedProfileIDs: Set<ConfigProfile.ID>
    @Binding var isBusy: Bool
    @Binding var statusMessage: String
    
    // Local selection state
    @State private var selectedTargetCategory: Int = 0
    
    // Callbacks to trigger data refreshes
    var onRefresh: () async -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status Header
                HStack {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { Task { await onRefresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Data")
                }
                
                Divider()
                
                // Group 1: Categorisation
                VStack(alignment: .leading, spacing: 10) {
                    Text("Categorisation")
                        .font(.headline)
                    
                    Text("Move selected profiles to:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Category", selection: $selectedTargetCategory) {
                        Text("Select a Category...").tag(0)
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .labelsHidden()
                    
                    Button(action: performBulkMove) {
                        Text("Move \(selectedProfileIDs.count) Profile(s)")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedProfileIDs.isEmpty || selectedTargetCategory == 0 || isBusy)
                }
                
                Divider()
                
                // Group 2: Deletion
                VStack(alignment: .leading, spacing: 10) {
                    Text("Danger Zone")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Button(action: performBulkDelete) {
                        Label("Delete \(selectedProfileIDs.count) Selected", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(selectedProfileIDs.isEmpty || isBusy)
                }
            }
        }
    }
    
    // MARK: - Actions Logic
    
    func performBulkMove() {
        guard selectedTargetCategory != 0 else { return }
        isBusy = true
        let count = selectedProfileIDs.count
        statusMessage = "Moving \(count) profiles..."
        
        Task {
            var successCount = 0
            for id in selectedProfileIDs {
                do {
                    try await api.moveProfile(id, toCategoryID: selectedTargetCategory)
                    successCount += 1
                } catch {
                    print("Failed to move \(id)")
                }
            }
            await onRefresh()
            await MainActor.run {
                selectedProfileIDs.removeAll()
                isBusy = false
                statusMessage = "Moved \(successCount) of \(count) profiles."
            }
        }
    }
    
    func performBulkDelete() {
        isBusy = true
        let count = selectedProfileIDs.count
        statusMessage = "Deleting \(count) profiles..."
        
        Task {
            var successCount = 0
            for id in selectedProfileIDs {
                do {
                    try await api.deleteProfile(id: id)
                    successCount += 1
                } catch {
                    print("Failed to delete \(id)")
                }
            }
            await onRefresh()
            await MainActor.run {
                selectedProfileIDs.removeAll()
                isBusy = false
                statusMessage = "Deleted \(successCount) of \(count) profiles."
            }
        }
    }
}