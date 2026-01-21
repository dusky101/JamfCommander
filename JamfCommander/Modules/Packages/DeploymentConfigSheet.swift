//
//  DeploymentConfigSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI

struct DeploymentConfigSheet: View {
    @ObservedObject var api: JamfAPIService
    
    // Callbacks: (CategoryName, ScriptID, FeatureOnMain, DisplayInCategory)
    var onConfirm: (String, String, Bool, Bool) -> Void
    var onCancel: () -> Void
    
    // Data State
    @State private var categories: [Category] = []
    @State private var scripts: [ScriptRecord] = []
    @State private var isLoading = true
    
    // Selection State
    @State private var selectedCategory: Category?
    @State private var selectedScriptID: String?
    @State private var searchText = ""
    
    // Self Service Options
    @State private var featureOnMainPage = false
    @State private var displayInSelfServiceCategory = true
    
    // Category Creation
    @State private var isCreatingCategory = false
    @State private var newCategoryName = ""
    @State private var isSavingCategory = false
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Deployment Configuration")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if isLoading {
                ProgressView("Loading Jamf Data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    // Left: Category Picker
                    VStack(alignment: .leading, spacing: 0) {
                        Text("1. Select Target Category")
                            .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            .padding(8)
                        
                        List(selection: $selectedCategory) {
                            ForEach(filteredCategories) { category in
                                HStack {
                                    Image(systemName: "folder")
                                    Text(category.name)
                                    Spacer()
                                    if selectedCategory?.id == category.id {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                                .tag(category)
                            }
                        }
                        .searchable(text: $searchText)
                        
                        Divider()
                        
                        // New Category Input
                        if isCreatingCategory {
                            HStack {
                                TextField("Name", text: $newCategoryName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") { createCategory() }
                                    .disabled(newCategoryName.isEmpty || isSavingCategory)
                                Button(action: { isCreatingCategory = false }) {
                                    Image(systemName: "xmark")
                                }.buttonStyle(.plain)
                            }
                            .padding(8)
                        } else {
                            Button(action: { isCreatingCategory = true }) {
                                Label("New Category", systemImage: "plus")
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                    }
                    .frame(width: 250)
                    
                    Divider()
                    
                    // Right: Script & Options Picker
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Script Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("2. Select Installomator Script")
                                .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            
                            if scripts.isEmpty {
                                Text("No scripts found in Jamf.")
                                    .foregroundColor(.red)
                            } else {
                                Picker("", selection: $selectedScriptID) {
                                    Text("Select a script...").tag(String?.none)
                                    ForEach(scripts) { script in
                                        Text(script.name).tag(Optional(script.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                        
                        Divider()
                        
                        // Self Service Options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("3. Self Service Options")
                                .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            
                            Toggle("Feature on Main Page", isOn: $featureOnMainPage)
                                .toggleStyle(.switch)
                            
                            Toggle("Display in '\(selectedCategory?.name ?? "Selected Category")'", isOn: $displayInSelfServiceCategory)
                                .toggleStyle(.switch)
                                .disabled(selectedCategory == nil)
                        }
                        
                        Spacer()
                        
                        // Summary Box
                        if let scriptID = selectedScriptID,
                           let script = scripts.first(where: { $0.id == scriptID }) {
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Summary:")
                                    .font(.caption).bold()
                                
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                                    GridRow {
                                        Text("Script:").foregroundColor(.secondary)
                                        Text(script.name).bold()
                                    }
                                    GridRow {
                                        Text("Self Service:").foregroundColor(.secondary)
                                        Text(featureOnMainPage ? "Featured" : "Standard")
                                    }
                                }
                                .font(.caption)
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Deploy Policies") {
                    if let cat = selectedCategory, let scriptId = selectedScriptID {
                        onConfirm(cat.name, scriptId, featureOnMainPage, displayInSelfServiceCategory)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCategory == nil || selectedScriptID == nil)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 650, height: 550)
        .onAppear(perform: loadData)
    }
    
    // MARK: - Logic
    
    func loadData() {
        Task {
            // FIXED: Tiny delay to allow sheet animation to finish before heavy lifting
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            
            do {
                async let fetchedCats = api.fetchCategories()
                async let fetchedScripts = api.fetchScripts()
                
                let (cats, scrts) = try await (fetchedCats, fetchedScripts)
                
                await MainActor.run {
                    self.categories = cats.sorted { $0.name < $1.name }
                    self.scripts = scrts.sorted { $0.name < $1.name }
                    
                    if let match = scrts.first(where: { $0.name.localizedCaseInsensitiveContains("Installomator") }) {
                        self.selectedScriptID = match.id
                    }
                    
                    self.isLoading = false
                }
            } catch {
                print("Error loading config data: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
    
    func createCategory() {
        guard !newCategoryName.isEmpty else { return }
        isSavingCategory = true
        Task {
            try? await api.createCategory(name: newCategoryName)
            let freshCats = try? await api.fetchCategories()
            await MainActor.run {
                if let fresh = freshCats {
                    self.categories = fresh.sorted { $0.name < $1.name }
                    if let new = fresh.first(where: { $0.name == newCategoryName }) {
                        self.selectedCategory = new
                    }
                }
                self.isCreatingCategory = false
                self.newCategoryName = ""
                self.isSavingCategory = false
            }
        }
    }
}
