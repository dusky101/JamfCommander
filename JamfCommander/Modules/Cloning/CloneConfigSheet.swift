//
//  CloneConfigSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 23/02/2026.
//

import SwiftUI

// MARK: - Clone Configuration Model

struct CloneConfiguration {
    let targetCategoryID: Int
    let stripScope: Bool
    let stripTriggers: Bool
    let stripFrequency: Bool
    let disableSelfService: Bool
}

// MARK: - Clone Configuration Sheet

struct CloneConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var api: JamfAPIService
    
    let mode: ActionMode
    let itemCount: Int
    @Binding var categories: [Category]
    let onConfirm: (CloneConfiguration) -> Void
    
    @State private var selectedCategory: Category?
    @State private var showCategoryCreation = false
    @State private var newCategoryName = ""
    @State private var isCreatingCategory = false
    @State private var categoryCreationError: String?
    
    // Strip options (all enabled by default)
    @State private var stripScope = true
    @State private var stripTriggers = true  // Policies only
    @State private var stripFrequency = true // Policies only
    @State private var disableSelfService = true // Policies only
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            VStack(spacing: 8) {
                Text("Clone Configuration")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Cloning \(itemCount) \(mode == .profiles ? "profile" : "policy")\(itemCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
            
            // MARK: - Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // MARK: - Categorisation Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Categorisation", systemImage: "folder")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Select the category for cloned items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Category Selection Menu
                        Menu {
                            ForEach(categories) { category in
                                Button(category.name) {
                                    selectedCategory = category
                                }
                            }
                        } label: {
                            HStack {
                                Text(selectedCategory?.name ?? "Select Category...")
                                    .foregroundColor(selectedCategory == nil ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .menuStyle(.borderlessButton)
                        
                        // Create New Category Button
                        if !showCategoryCreation {
                            Button(action: { showCategoryCreation = true }) {
                                Label("Create New Category", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        }
                        
                        // Inline Category Creation
                        if showCategoryCreation {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Category Name", text: $newCategoryName)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Button("Create") {
                                        Task {
                                            await createCategory()
                                        }
                                    }
                                    .disabled(newCategoryName.isEmpty || isCreatingCategory)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    
                                    Button("Cancel") {
                                        showCategoryCreation = false
                                        newCategoryName = ""
                                        categoryCreationError = nil
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                if let error = categoryCreationError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(12)
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .cornerRadius(12)
                    .liquidGlass()
                    
                    // MARK: - Strip Options Section
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Clone Options", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Configure what to strip from cloned items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Remove Scope Checkbox
                        Toggle(isOn: $stripScope) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Remove Scope")
                                    .font(.subheadline)
                                Text("Clones will be unscoped (not deployed to any computers)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(.vertical, 8)
                        
                        // Policy-specific options
                        if mode == .policies {
                            Divider()
                            
                            Toggle(isOn: $stripTriggers) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Remove Triggers")
                                        .font(.subheadline)
                                    Text("Clones will have no automatic triggers (login, logout, check-in, etc.)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, 8)
                            
                            Divider()
                            
                            Toggle(isOn: $stripFrequency) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Remove Frequency")
                                        .font(.subheadline)
                                    Text("Clones will be set to 'Once per computer'")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, 8)
                            
                            Divider()
                            
                            Toggle(isOn: $disableSelfService) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Disable Self Service")
                                        .font(.subheadline)
                                    Text("Clones will not be available in Self Service (use_for_self_service = false)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .cornerRadius(12)
                    .liquidGlass()
                    
                    // MARK: - Info Box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clone Behaviour")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("New items will be named 'Copy of [Original Name]' and will be disabled by default for safety. All other settings will be preserved unless stripped above.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding()
            }
            
            Divider()
            
            // MARK: - Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Clone Items") {
                    confirmClone()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(selectedCategory == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .frame(width: 500, height: 600)
        .appBackground()
    }
    
    // MARK: - Actions
    
    private func createCategory() async {
        guard !newCategoryName.isEmpty else { return }
        
        isCreatingCategory = true
        categoryCreationError = nil
        
        do {
            try await api.createCategory(name: newCategoryName)
            
            // Refresh categories list
            let updatedCategories = try await api.fetchCategories()
            
            await MainActor.run {
                categories = updatedCategories
                
                // Auto-select the newly created category
                if let newCategory = categories.first(where: { $0.name == newCategoryName }) {
                    selectedCategory = newCategory
                }
                
                // Reset creation state
                showCategoryCreation = false
                newCategoryName = ""
                isCreatingCategory = false
            }
        } catch {
            await MainActor.run {
                categoryCreationError = "Failed to create category: \(error.localizedDescription)"
                isCreatingCategory = false
            }
        }
    }
    
    private func confirmClone() {
        guard let category = selectedCategory else { return }
        
        let config = CloneConfiguration(
            targetCategoryID: category.id,
            stripScope: stripScope,
            stripTriggers: stripTriggers,
            stripFrequency: stripFrequency,
            disableSelfService: disableSelfService
        )
        
        onConfirm(config)
        dismiss()
    }
}
