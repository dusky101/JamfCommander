//
//  DashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var api: JamfAPIService
    
    // NEW: Binding to control navigation from the stats
    @Binding var currentModule: AppModule
    
    // Stats State
    @State private var computerCount = 0
    @State private var profileCount = 0
    @State private var scriptCount = 0
    @State private var policyCount = 0
    
    // Data Lists
    @State private var categories: [Category] = []
    @State private var computers: [BasicComputerRecord] = [] // For Device Status
    
    // UI State
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showCategorySheet = false
    @State private var categoryToEdit: Category?
    @State private var categoryNameInput = ""
    @State private var isSaving = false
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirmation = false
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - 1. Hero Stats Grid (Clickable)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    
                    Button(action: { currentModule = .computers }) {
                        StatCard(title: "Computers", count: computerCount, icon: "desktopcomputer", color: .blue)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { currentModule = .policies }) {
                        StatCard(title: "Policies", count: policyCount, icon: "scroll.fill", color: .purple)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { currentModule = .profiles }) {
                        StatCard(title: "Profiles", count: profileCount, icon: "doc.text.fill", color: .orange)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { currentModule = .scripts }) {
                        StatCard(title: "Scripts", count: scriptCount, icon: "applescript.fill", color: .gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top)
                
                Divider().padding(.horizontal)
                
                // MARK: - 2. Category Manager
                VStack(spacing: 16) {
                    HStack {
                        Label("Categories", systemImage: "folder.fill")
                            .font(.title2).fontWeight(.bold)
                        Spacer()
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField("Search...", text: $searchText)
                                .textFieldStyle(.plain).frame(width: 150)
                        }
                        .padding(6).background(Color.black.opacity(0.1)).cornerRadius(8)
                        
                        Button(action: { openCategorySheet(for: nil) }) {
                            Label("New Category", systemImage: "plus").fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(filteredCategories) { category in
                            CategoryTile(
                                category: category,
                                onEdit: { openCategorySheet(for: category) },
                                onDelete: { confirmDelete(category) }
                            )
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // MARK: - 3. Device Status (NEW)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Device Status", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.title2).fontWeight(.bold)
                        Spacer()
                        Text("Recent Check-ins")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    
                    // Device List Box
                    VStack(spacing: 0) {
                        if computers.isEmpty {
                            Text("No computers found.").padding()
                                .foregroundColor(.secondary)
                        } else {
                            // Show first 10 for dashboard summary
                            ForEach(computers.prefix(10), id: \.id) { comp in
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                        .foregroundColor(.secondary)
                                        .font(.title3)
                                    Text(comp.name)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    // Mock Status Badge (Green for OK)
                                    HStack(spacing: 6) {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                        Text("Active")
                                    }
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .padding()
                                
                                if comp.id != computers.prefix(10).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .background(Color.clear)
        .task { await refreshDashboard() }
        
        // MARK: - Sheets
        .sheet(isPresented: $showCategorySheet) {
            VStack(spacing: 20) {
                Text(categoryToEdit == nil ? "New Category" : "Edit Category").font(.headline)
                TextField("Category Name", text: $categoryNameInput)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                    .onSubmit { Task { await saveCategory() } }
                HStack {
                    Button("Cancel") { showCategorySheet = false }
                        .keyboardShortcut(.escape, modifiers: [])
                    Button("Save") { Task { await saveCategory() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(categoryNameInput.isEmpty || isSaving)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding().frame(width: 350, height: 200)
        }
        .confirmationDialog("Delete Category?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete '\(categoryToDelete?.name ?? "")'", role: .destructive) {
                if let cat = categoryToDelete { Task { await deleteCategory(cat) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will verify if the category is empty before deletion.")
        }
    }
    
    // MARK: - Actions
    
    func refreshDashboard() async {
        isLoading = true
        do {
            async let fetchedComputers = api.fetchDashboardComputers()
            async let fetchedProfiles = api.fetchProfiles()
            async let fetchedScripts = api.fetchScripts()
            async let fetchedPolicies = api.fetchPolicies()
            async let fetchedCategories = api.fetchCategories()
            
            let (comps, profs, scripts, pols, cats) = try await (fetchedComputers, fetchedProfiles, fetchedScripts, fetchedPolicies, fetchedCategories)
            
            await MainActor.run {
                self.computers = comps
                self.computerCount = comps.count
                self.profileCount = profs.count
                self.scriptCount = scripts.count
                self.policyCount = pols.count
                self.categories = cats.sorted { $0.name < $1.name }
                self.isLoading = false
            }
        } catch {
            print("Dashboard Refresh Error: \(error)")
            self.isLoading = false
        }
    }
    
    func openCategorySheet(for category: Category?) {
        categoryToEdit = category
        categoryNameInput = category?.name ?? ""
        showCategorySheet = true
    }
    
    func saveCategory() async {
        isSaving = true
        do {
            if let existing = categoryToEdit {
                try await api.updateCategory(id: existing.id, newName: categoryNameInput)
            } else {
                try await api.createCategory(name: categoryNameInput)
            }
            showCategorySheet = false
            await refreshDashboard()
        } catch {
            print("Failed to save category: \(error)")
        }
        isSaving = false
    }
    
    func confirmDelete(_ category: Category) {
        categoryToDelete = category
        showDeleteConfirmation = true
    }
    
    func deleteCategory(_ category: Category) async {
        do {
            try await api.deleteCategory(id: category.id)
            await refreshDashboard()
        } catch {
            print("Failed to delete category: \(error)")
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                Spacer()
                Text("\(count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .liquidGlass(.card)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { isHovering = $0 }
        // Make the cursor point so it feels clickable
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct CategoryTile: View {
    let category: Category
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill").foregroundColor(.blue)
            Text(category.name).fontWeight(.medium).lineLimit(1)
            Spacer()
            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill").foregroundColor(.red.opacity(0.8))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .onHover { isHovering = $0 }
    }
}
