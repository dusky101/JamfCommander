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
    @State private var isExporting = false
    @State private var showExportProgress = false
    @StateObject private var exportProgress = ExportProgress()
    @State private var isCategoryManagerExpanded = true
    @State private var expandedDomains: Set<String> = [] // Track which domain groups are expanded
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - 1. Hero Stats Grid (Clickable)
                HStack(alignment: .top, spacing: 16) {
                    // Stats Grid (Leading)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], alignment: .leading, spacing: 16) {
                        
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
                    
                    Spacer()
                    
                    // Export All Button (Trailing)
                    Button(action: { exportAllData() }) {
                        ExportAllCard(isExporting: isExporting)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .frame(width: 140)
                }
                .padding(.horizontal)
                .padding(.top)
                
                Divider().padding(.horizontal)
                
                // MARK: - 2. Category Manager
                VStack(spacing: 16) {
                    HStack {
                        Button(action: { withAnimation { isCategoryManagerExpanded.toggle() } }) {
                            HStack(spacing: 8) {
                                Image(systemName: isCategoryManagerExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption).fontWeight(.bold)
                                Label("Categories", systemImage: "folder.fill")
                                    .font(.title2).fontWeight(.bold)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if isCategoryManagerExpanded {
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
                    }
                    
                    if isCategoryManagerExpanded {
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
                    
                    // Device List Box - Grouped by Email Domain
                    if computers.isEmpty {
                        VStack {
                            Text("No computers found.").padding()
                                .foregroundColor(.secondary)
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    } else {
                        // Group computers by email domain
                        let groupedComputers = Dictionary(grouping: computers.prefix(20), by: { $0.emailDomain })
                        let sortedDomains = groupedComputers.keys.sorted()
                        
                        VStack(spacing: 12) {
                            ForEach(sortedDomains, id: \.self) { domain in
                                let computersInDomain = groupedComputers[domain] ?? []
                                
                                VStack(alignment: .leading, spacing: 0) {
                                    // Domain Header (Collapsible)
                                    Button(action: {
                                        withAnimation {
                                            if expandedDomains.contains(domain) {
                                                expandedDomains.remove(domain)
                                            } else {
                                                expandedDomains.insert(domain)
                                            }
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "envelope.fill")
                                                .foregroundColor(.blue)
                                            
                                            Text(domain)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Text("\(computersInDomain.count)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.secondary)
                                                .rotationEffect(.degrees(expandedDomains.contains(domain) ? 90 : 0))
                                        }
                                        .padding(12)
                                        .background(Color.blue.opacity(0.05))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Computers in this domain
                                    if expandedDomains.contains(domain) {
                                        VStack(spacing: 12) {
                                            ForEach(computersInDomain) { comp in
                                                HStack {
                                                    Image(systemName: "desktopcomputer")
                                                        .foregroundColor(.secondary)
                                                        .font(.title3)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(comp.name)
                                                            .fontWeight(.medium)
                                                            .foregroundColor(.primary)
                                                        
                                                        if let email = comp.email, !email.isEmpty {
                                                            HStack(spacing: 4) {
                                                                Image(systemName: "envelope")
                                                                    .font(.caption2)
                                                                Text(email)
                                                            }
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        } else if let username = comp.username, !username.isEmpty {
                                                            HStack(spacing: 4) {
                                                                Image(systemName: "person.crop.circle")
                                                                    .font(.caption2)
                                                                Text(username)
                                                            }
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    // Status Badge
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
                                                .padding(12)
                                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                                                .cornerRadius(8)
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            // Expand all domains by default
                            let domains = Set(computers.prefix(20).map { $0.emailDomain })
                            expandedDomains = domains
                        }
                    }
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
        .sheet(isPresented: $showExportProgress) {
            ExportProgressSheet(isPresented: $showExportProgress, progress: exportProgress)
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
    
    func exportAllData() {
        isExporting = true
        exportProgress.reset()
        showExportProgress = true
        
        Task {
            _ = await ExportService.exportAllDataToZip(api: api, progress: exportProgress)
            
            // Wait a moment to show completion state
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await MainActor.run {
                isExporting = false
                showExportProgress = false // Auto-dismiss sheet
            }
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
        .liquidGlass(cornerRadius: 12)
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
struct ExportAllCard: View {
    let isExporting: Bool
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 36, height: 36)
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
            }
            
            Text(isExporting ? "Exporting..." : "Export All")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isExporting ? .secondary : .primary)
            
            Text(isExporting ? "Please wait..." : "Download Data")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .liquidGlass(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(isHovering ? 0.5 : 0.2), lineWidth: 2)
        )
        .scaleEffect(isHovering && !isExporting ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { isHovering = $0 }
        .onHover { inside in
            if inside && !isExporting { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

