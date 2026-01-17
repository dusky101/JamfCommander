//
//  ProfileInspectorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ProfileInspectorView: View {
    let profileId: Int
    @ObservedObject var api: JamfAPIService
    @Environment(\.dismiss) var dismiss
    
    // Data State
    @State private var jsonContent: String = "Loading..."
    // Changed from just 'scopeInfo' to full 'profileDetail' so we can access the Name
    @State private var profileDetail: ProfileDetail?
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Edit State
    @State private var isEditingScope = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            ZStack {
                // 1. Left: ID & Label
                HStack {
                    VStack(alignment: .leading) {
                        Text("Inspector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.caption2)
                            Text("ID: \(profileId)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // 2. Center: Profile Name (The requested update)
                Text(profileDetail?.general.name ?? "Loading...")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
                
                // 3. Right: Actions
                HStack {
                    Spacer()
                    
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                    
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- MAIN CONTENT ---
            if isLoading {
                loadingView
            } else {
                HSplitView {
                    // LEFT PANE: Scope & Info (Fixed ~33% Width)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                scopeSection
                            }
                            .padding()
                        }
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.02))
                    
                    // RIGHT PANE: Code Editor (Takes remaining ~67%)
                    // Note: Ensure you update JSONEditorView.swift below for scrolling to work!
                    JSONEditorView(
                        title: "Raw Source (JSON)",
                        text: $jsonContent,
                        onSave: { newJson in
                            saveChanges(newJson)
                        }
                    )
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
            }
            
            // Error Banner (if save fails)
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
            }
        }
        .frame(width: 950, height: 700)
        .liquidGlass(.panel)
        .task {
            await loadData()
        }
    }
    
    // MARK: - Subviews
    
    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching Profile Data...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
    
    var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header with Edit Toggle
            HStack {
                Label("Deployment Scope", systemImage: "scope")
                    .font(.headline)
                Spacer()
                Button(isEditingScope ? "Done" : "Edit") {
                    withAnimation { isEditingScope.toggle() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(isEditingScope ? .blue : .secondary)
            }
            
            if let scope = profileDetail?.scope {
                
                // 1. All Computers Toggle
                if isEditingScope {
                    Toggle(isOn: Binding(
                        get: { scope.all_computers },
                        set: { newValue in
                            print("Toggled All Computers to: \(newValue)")
                        }
                    )) {
                        Text("Deploy to All Computers")
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)
                } else {
                    // Read-only Badges
                    if scope.all_computers {
                        scopeBadge(
                            title: "Global Deployment",
                            subtitle: "Installed on all computers.",
                            icon: "globe",
                            color: .green
                        )
                    } else {
                        scopeBadge(
                            title: "Targeted Deployment",
                            subtitle: "Restricted to specific groups.",
                            icon: "target",
                            color: .orange
                        )
                    }
                }
                
                // 2. Targeted Computers List
                if !scope.all_computers {
                    if let computers = scope.computers, !computers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TARGETED COMPUTERS (\(computers.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                            
                            ForEach(computers) { computer in
                                computerRow(name: computer.name, id: computer.id)
                            }
                        }
                    } else if !isEditingScope {
                        Text("No specific computers targeted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    // Add Button (Visual only for now)
                    if isEditingScope {
                        Button(action: { /* Add logic */ }) {
                            Label("Add Computer", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                }
            } else {
                Text("No scope information returned.")
                    .italic()
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // Helper for Badges
    func scopeBadge(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .padding(.trailing, 4)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).opacity(0.8)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    // Helper for Computer Rows
    func computerRow(name: String, id: Int) -> some View {
        HStack {
            // Delete Button (Only visible when editing)
            if isEditingScope {
                Button(action: {
                    print("Remove computer \(id)")
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Image(systemName: "desktopcomputer")
                .foregroundColor(.secondary)
            Text(name)
                .font(.subheadline)
            Spacer()
            Text("#\(id)")
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
    
    // MARK: - Actions
    
    func loadData() async {
        do {
            async let fetchedJSON = api.fetchProfileJSON(id: profileId)
            async let fetchedDetail = api.fetchProfileScope(id: profileId)
            
            let (json, detail) = try await (fetchedJSON, fetchedDetail)
            
            self.jsonContent = json
            self.profileDetail = detail
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load data."
            self.isLoading = false
        }
    }
    
    func saveChanges(_ newJson: String) {
        isSaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
        }
    }
}
