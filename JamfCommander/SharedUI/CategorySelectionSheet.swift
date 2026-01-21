//
//  CategorySelectionSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI

struct CategorySelectionSheet: View {
    @ObservedObject var api: JamfAPIService
    
    // Callbacks
    var onCategorySelected: (String) -> Void
    var onCancel: () -> Void
    
    // State
    @State private var categories: [Category] = []
    @State private var isLoading = true
    @State private var selectedCategory: Category?
    @State private var searchText = ""
    
    // Creation State
    @State private var isCreatingNew = false
    @State private var newCategoryName = ""
    @State private var isSaving = false
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Target Category")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if isLoading {
                ProgressView("Loading Categories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List
                List(selection: $selectedCategory) {
                    ForEach(filteredCategories) { category in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                            Text(category.name)
                            Spacer()
                            if selectedCategory?.id == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .tag(category) // Required for selection
                        .padding(.vertical, 4)
                    }
                }
                .searchable(text: $searchText, placement: .sidebar) // Simple search
            }
            
            Divider()
            
            // Footer: Create & Confirm
            VStack(spacing: 12) {
                
                // Create New Section
                if isCreatingNew {
                    HStack {
                        TextField("New Category Name", text: $newCategoryName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Create & Select") {
                            createCategory()
                        }
                        .disabled(newCategoryName.isEmpty || isSaving)
                        
                        Button(action: { isCreatingNew = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: { isCreatingNew = true }) {
                        Label("Create New Category", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                
                // Confirm Button
                Button(action: {
                    if let cat = selectedCategory {
                        onCategorySelected(cat.name)
                    }
                }) {
                    Text("Deploy to Selected")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedCategory == nil)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 400, height: 500)
        .onAppear(perform: loadCategories)
    }
    
    // MARK: - Logic
    
    func loadCategories() {
        Task {
            do {
                let fetched = try await api.fetchCategories()
                await MainActor.run {
                    self.categories = fetched.sorted { $0.name < $1.name }
                    self.isLoading = false
                }
            } catch {
                print("Failed to fetch categories: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
    
    func createCategory() {
        guard !newCategoryName.isEmpty else { return }
        isSaving = true
        
        Task {
            do {
                // 1. Create it via API
                try await api.createCategory(name: newCategoryName)
                
                // 2. Reload list
                let fetched = try await api.fetchCategories()
                
                await MainActor.run {
                    self.categories = fetched.sorted { $0.name < $1.name }
                    
                    // 3. Auto-select the new one
                    if let newCat = self.categories.first(where: { $0.name == newCategoryName }) {
                        self.selectedCategory = newCat
                    }
                    
                    self.isCreatingNew = false
                    self.newCategoryName = ""
                    self.isSaving = false
                }
            } catch {
                print("Failed to create category: \(error)")
                await MainActor.run { self.isSaving = false }
            }
        }
    }
}
