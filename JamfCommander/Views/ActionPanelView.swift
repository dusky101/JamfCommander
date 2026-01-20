//
//  ActionPanelView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

enum ActionMode {
    case profiles
    case policies
}

struct ActionPanelView: View {
    @ObservedObject var api: JamfAPIService
    
    // Configuration
    let mode: ActionMode
    let categories: [Category]
    
    // Data Sources
    var profiles: [ConfigProfile] = []
    var policies: [Policy] = []
    
    // Bindings
    @Binding var selectedIDs: Set<Int>
    @Binding var isBusy: Bool
    @Binding var statusMessage: String
    
    // Callbacks
    var onRefresh: () async -> Void
    
    // Local State
    @State private var selectedTargetCategory: Category? = nil
    @State private var confirmation: ConfirmationData?
    
    // Result Sheet State
    @State private var resultsLog: [OperationResult] = []
    @State private var showResultsSheet = false
    
    @AppStorage("jamfInstanceURL") private var instanceURL = ""
    
    // Scope Action State (Profiles Only)
    @State private var selectedScopeAction: ScopeAction?
    
    // Define scope actions
    enum ScopeAction: String, CaseIterable, Identifiable {
        case allComputers = "All Computers"
        case removeScope = "Remove Scope"
        // Note: "User Groups" would require fetching groups and selecting them,
        // which we can implement later if needed
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .allComputers: return "globe"
            case .removeScope: return "xmark.circle"
            }
        }
        
        var color: Color {
            switch self {
            case .allComputers: return .green
            case .removeScope: return .orange
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 20) {
            
            // MARK: - Left: Selection Info
            VStack(alignment: .leading, spacing: 6) {
                Label("Bulk Actions", systemImage: "checklist")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(selectedIDs.count) items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
                
                Spacer()
                
                Button(action: { withAnimation { selectedIDs.removeAll() } }) {
                    Label("Cancel Selection", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .frame(width: 140, alignment: .leading)
            
            Divider()
            
            // MARK: - Center: Categorization
            VStack(alignment: .leading, spacing: 12) {
                Text("Categorisation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                HStack {
                    Menu {
                        ForEach(categories) { category in
                            Button(category.name) { selectedTargetCategory = category }
                        }
                    } label: {
                        HStack {
                            Text(selectedTargetCategory?.name ?? "Select Category...")
                                .foregroundColor(selectedTargetCategory == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(maxWidth: 200)
                    
                    Button(action: requestMove) {
                        Text("Move")
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(selectedTargetCategory == nil || isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // MARK: - Center-Right: Scope Management (Profiles Only)
            if mode == .profiles {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scope Management")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Menu {
                            ForEach(ScopeAction.allCases) { action in
                                Button {
                                    selectedScopeAction = action
                                } label: {
                                    Label(action.rawValue, systemImage: action.icon)
                                }
                            }
                        } label: {
                            HStack {
                                if let action = selectedScopeAction {
                                    Image(systemName: action.icon)
                                        .foregroundColor(action.color)
                                    Text(action.rawValue)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Select Scope Action...")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(maxWidth: 200)
                        
                        Button(action: requestScopeChange) {
                            Text("Apply Scope")
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(selectedScopeAction == nil || isBusy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
            }
            
            // MARK: - Right: Danger Zone
            VStack(alignment: .leading, spacing: 12) {
                Text("Danger Zone")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red.opacity(0.8))
                
                Button(action: requestDelete) {
                    Label("Delete Selection", systemImage: "trash.fill")
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isBusy)
            }
            .frame(width: 160)
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, 10)
        
        // Confirmation Logic
        .commanderConfirmation(data: $confirmation)
        
        // Result Sheet Logic
        .sheet(isPresented: $showResultsSheet) {
            OperationResultView(
                title: "Operation Complete",
                results: resultsLog,
                onDismiss: {
                    showResultsSheet = false
                    selectedIDs.removeAll()
                    selectedTargetCategory = nil
                    selectedScopeAction = nil // Clear scope action too
                    Task { await onRefresh() }
                }
            )
        }
    }
    
    // MARK: - Logic
    
    func requestScopeChange() {
        guard let scopeAction = selectedScopeAction else { return }
        let count = selectedIDs.count
        
        let actionDescription: String
        switch scopeAction {
        case .allComputers:
            actionDescription = "set the scope to 'All Computers'"
        case .removeScope:
            actionDescription = "remove all scope (no computers will be targeted)"
        }
        
        confirmation = ConfirmationData(
            title: "Confirm Scope Change",
            message: "You are about to \(actionDescription) for \(count) profile\(count == 1 ? "" : "s").\n\nThis will update the deployment targets.\n\nPlease confirm this action.",
            actionTitle: "Update Scope",
            role: .none,
            action: { performBulkScopeChange() }
        )
    }
    
    func requestMove() {
        guard let category = selectedTargetCategory else { return }
        let count = selectedIDs.count
        let typeName = mode == .profiles ? "profiles" : "policies"
        
        confirmation = ConfirmationData(
            title: "Confirm Move",
            message: "You are about to move \(count) \(typeName) to the '\(category.name)' category.\n\nPlease confirm this action.",
            actionTitle: "Move Items",
            role: .none,
            action: { performBulkMove() }
        )
    }
    
    func requestDelete() {
        let count = selectedIDs.count
        let typeName = mode == .profiles ? "profiles" : "policies"
        let url = instanceURL.isEmpty ? "your Jamf instance" : instanceURL
        
        confirmation = ConfirmationData(
            title: "⚠️ Confirm Deletion",
            message: "Warning: You are about to DELETE \(count) \(typeName) from \(url).\n\nYou will NOT be able to restore them.\n\nPlease confirm below.",
            actionTitle: "Delete Forever",
            role: .destructive,
            action: { performBulkDelete() }
        )
    }
    
    func performBulkScopeChange() {
        guard let scopeAction = selectedScopeAction else { return }
        isBusy = true
        statusMessage = "Processing..."
        resultsLog = []
        
        Task {
            for id in selectedIDs {
                var name = "Item #\(id)"
                
                // Get profile name
                if let p = profiles.first(where: { $0.id == id }) {
                    name = p.name
                }
                
                do {
                    // Call appropriate API method based on scope action
                    switch scopeAction {
                    case .allComputers:
                        try await api.setProfileScopeToAllComputers(id)
                    case .removeScope:
                        try await api.removeProfileScope(id)
                    }
                    
                    resultsLog.append(OperationResult(
                        itemName: name,
                        success: true,
                        error: nil,
                        fromCategory: nil,
                        toCategory: "Scope: \(scopeAction.rawValue)"
                    ))
                } catch {
                    resultsLog.append(OperationResult(
                        itemName: name,
                        success: false,
                        error: "\(error)"
                    ))
                }
            }
            
            await MainActor.run {
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }
    
    func performBulkMove() {
        guard let targetCategory = selectedTargetCategory else { return }
        isBusy = true
        statusMessage = "Processing..."
        resultsLog = []
        
        Task {
            for id in selectedIDs {
                var name = "Item #\(id)"
                var oldCategory = "Unknown"
                
                // Get Metadata based on Mode
                if mode == .profiles {
                    if let p = profiles.first(where: { $0.id == id }) {
                        name = p.name
                        oldCategory = p.categoryName
                    }
                } else {
                    if let p = policies.first(where: { $0.id == id }) {
                        name = p.name
                        oldCategory = p.categoryName ?? "No Category"
                    }
                }
                
                do {
                    // Call API based on Mode
                    if mode == .profiles {
                        try await api.moveProfile(id, toCategoryID: targetCategory.id)
                    } else {
                        try await api.movePolicy(id: id, toCategoryID: targetCategory.id) // Corrected Label Usage
                    }
                    
                    resultsLog.append(OperationResult(
                        itemName: name,
                        success: true,
                        error: nil,
                        fromCategory: oldCategory,
                        toCategory: targetCategory.name
                    ))
                } catch {
                    resultsLog.append(OperationResult(itemName: name, success: false, error: "\(error)"))
                }
            }
            
            await MainActor.run {
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }
    
    func performBulkDelete() {
        isBusy = true
        statusMessage = "Processing..."
        resultsLog = []
        
        Task {
            for id in selectedIDs {
                do {
                    if mode == .profiles {
                        try await api.deleteProfile(id: id)
                    } else {
                        try await api.deletePolicy(id: id)
                    }
                    resultsLog.append(OperationResult(itemName: "ID \(id)", success: true, error: nil))
                } catch {
                    resultsLog.append(OperationResult(itemName: "ID \(id)", success: false, error: "\(error)"))
                }
            }
            
            await MainActor.run {
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }
}
