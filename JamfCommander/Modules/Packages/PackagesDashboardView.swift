//
//  PackagesDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct PackagesDashboardView: View {
    @StateObject private var matcher = PackageMatchingService.shared
    @ObservedObject var api: JamfAPIService
    
    // Selection & filtering
    @State private var selection = Set<String>()  // Changed from UUID to String
    @State private var searchText = ""
    @State private var selectedPlatformFilter: String = "All"
    @State private var showAllLabels = false // Toggle between matched items and all labels
    
    // Multi-select support
    @State private var lastSelectedID: String? = nil  // Changed from UUID to String
    
    // Action States
    @State private var creationStatus: String = ""
    @State private var isCreatingPolicies = false
    @State private var showResultsSheet = false
    @State private var deploymentResults: [OperationResult] = []
    // Removed cancellables as we are using async/await now
    
    // Config Sheet State
    @State private var showConfigSheet = false
    @State private var animateImportIcon = false
    
    // MARK: - Computed Logic
    var displayItems: [PackageDisplayItem] {
        if showAllLabels {
            // Show all labels from Installomator
            return matcher.allLabels.map { label in
                // Check if this label has a match
                let match = matcher.matches.first(where: { $0.matchedLabel == label })
                return PackageDisplayItem(label: label, matchedApp: match?.intuneApp)
            }
        } else {
            // Show only matched items
            return matcher.matches.map { match in
                PackageDisplayItem(label: match.matchedLabel, matchedApp: match.intuneApp)
            }
        }
    }
    
    var filteredItems: [PackageDisplayItem] {
        displayItems.filter { item in
            let textMatch = searchText.isEmpty ||
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            item.label.localizedCaseInsensitiveContains(searchText)
            
            let platformMatch = (selectedPlatformFilter == "All") ||
            (item.platform == selectedPlatformFilter) ||
            (!item.isMatched && selectedPlatformFilter == "Installomator")
            
            return textMatch && platformMatch
        }
    }
    
    var groupedItems: [(key: String, value: [PackageDisplayItem])] {
        let grouped = Dictionary(grouping: filteredItems) { $0.platform }
        return grouped.sorted { $0.key < $1.key }
    }
    
    // Keep original computed properties for backwards compatibility
    var filteredMatches: [PackageMatch] {
        matcher.matches.filter { match in
            let textMatch = searchText.isEmpty ||
            match.intuneApp.name.localizedCaseInsensitiveContains(searchText) ||
            match.matchedLabel.localizedCaseInsensitiveContains(searchText)
            
            let platformMatch = (selectedPlatformFilter == "All") ||
            (match.intuneApp.platform == selectedPlatformFilter)
            
            return textMatch && platformMatch
        }
    }
    
    var groupedMatches: [(key: String, value: [PackageMatch])] {
        let grouped = Dictionary(grouping: filteredMatches) { $0.intuneApp.platform }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var selectedMatches: [PackageMatch] {
        if showAllLabels {
            // In "show all" mode, we need to find matches by label name since IDs are different
            let selectedLabels = displayItems
                .filter { selection.contains($0.id) && $0.isMatched }
                .map { $0.label }
            
            return matcher.matches.filter { selectedLabels.contains($0.matchedLabel) }
        } else {
            // In matched mode, find matches by comparing their labels with selected display items
            let selectedLabels = displayItems
                .filter { selection.contains($0.id) }
                .map { $0.label }
            
            return matcher.matches.filter { selectedLabels.contains($0.matchedLabel) }
        }
    }
    
    // Helper to find PackageMatch for a display item
    func findMatch(for item: PackageDisplayItem) -> PackageMatch? {
        return matcher.matches.first { $0.matchedLabel == item.label }
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            if matcher.isProcessing {
                ProgressView("Analysing Inventory Matches...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matcher.matches.isEmpty {
                importDashboard
            } else {
                filterBar
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedItems, id: \.key) { group in
                            CollapsiblePackageSection(
                                title: group.key,
                                items: group.value,
                                selectedIDs: $selection,
                                onToggle: toggleSelection,
                                showAllMode: showAllLabels,
                                matcher: matcher
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 60)
                }
            }
            
            if !matcher.matches.isEmpty && !selection.isEmpty {
                actionFooter
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            DeploymentConfigSheet(
                api: api,
                onConfirm: { category, scriptID, featured, displayInCat in
                    showConfigSheet = false
                    deployPolicies(
                        category: category,
                        scriptID: scriptID,
                        featureOnMain: featured,
                        displayInCat: displayInCat
                    )
                },
                onCancel: {
                    showConfigSheet = false
                }
            )
        }
        .sheet(isPresented: $showResultsSheet) {
            OperationResultView(
                title: "Deployment Results",
                results: deploymentResults,
                onDismiss: {
                    showResultsSheet = false
                    deploymentResults = []
                }
            )
        }
    }
    
    // MARK: - Components
    var headerView: some View {
        HStack(spacing: 16) {
            Text("Package Migration Assistant")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            if !matcher.matches.isEmpty {
                // Toggle between matched and all labels
                Picker("View Mode", selection: $showAllLabels) {
                    Text("Matched Only").tag(false)
                    Text("All Labels").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 220)
                .onChange(of: showAllLabels) {
                    // Clear selection when switching modes
                    selection.removeAll()
                    lastSelectedID = nil
                }
                
                Button(action: { 
                    matcher.reset()
                    showAllLabels = false
                    selection.removeAll()
                    lastSelectedID = nil
                }) {
                    Label("New Session", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps or labels...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            Picker("Platform", selection: $selectedPlatformFilter) {
                Text("All Platforms").tag("All")
                Text("macOS").tag("macOS")
                Text("Windows").tag("Windows")
                if showAllLabels {
                    Text("Unmatched").tag("Installomator")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: showAllLabels ? 300 : 240)
            .animation(.default, value: showAllLabels)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .zIndex(1)
    }
    
    var importDashboard: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                        .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: animateImportIcon)
                    
                    Text("Import Inventory Data")
                        .font(.title)
                    Text("Drag and drop your files to identify Installomator candidates.")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                .onAppear { animateImportIcon = true }
                
                HStack(spacing: 20) {
                    ImportDropZone(
                        title: "Installomator Labels",
                        icon: "tag.fill",
                        acceptedTypes: [.plainText],
                        fileName: matcher.labelsFileName,
                        onImport: { url in matcher.loadLabels(from: url) }
                    )
                    ImportDropZone(
                        title: "Mac Apps (CSV)",
                        icon: "applelogo",
                        acceptedTypes: [.commaSeparatedText],
                        fileName: matcher.macAppsFileName,
                        onImport: { url in matcher.loadMacCSV(from: url) }
                    )
                    ImportDropZone(
                        title: "PC Apps (CSV)",
                        icon: "desktopcomputer",
                        acceptedTypes: [.commaSeparatedText],
                        fileName: matcher.pcAppsFileName,
                        onImport: { url in matcher.loadPCCSV(from: url) }
                    )
                }
                .padding(.horizontal)
                
                Button(action: { matcher.processMatches() }) {
                    Text("Analyse Matches")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(matcher.labelsFileName == nil || (matcher.macAppsFileName == nil && matcher.pcAppsFileName == nil))
                .controlSize(.large)
                
                Spacer()
            }
            .padding()
        }
    }
    
    var actionFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(selection.count) items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                if !creationStatus.isEmpty {
                    Text(creationStatus)
                        .font(.caption)
                        .foregroundColor(creationStatus.contains("Error") ? .red : .green)
                }
                
                Button(action: { showConfigSheet = true }) {
                    if isCreatingPolicies {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add to Jamf")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreatingPolicies)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    // MARK: - Logic
    
    func toggleSelection(id: String) {  // Changed from UUID to String
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        if isShiftPressed, let lastId = lastSelectedID {
            // Shift-Click: Select range
            let allVisibleItems = filteredItems
            
            if let lastIndex = allVisibleItems.firstIndex(where: { $0.id == lastId }),
               let currentIndex = allVisibleItems.firstIndex(where: { $0.id == id }) {
                
                let start = min(lastIndex, currentIndex)
                let end = max(lastIndex, currentIndex)
                
                let idsToSelect = allVisibleItems[start...end]
                    .filter { !showAllLabels || $0.isMatched } // Only select matched items in "show all" mode
                    .map { $0.id }
                
                selection.formUnion(idsToSelect)
            }
        } else {
            // Standard Toggle
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
            lastSelectedID = id
        }
    }
    
    // UPDATED: Async implementation with throttling
    // Deploy all selected items (both matched and unmatched) - ALL have Installomator labels
    func deployPolicies(category: String, scriptID: String, featureOnMain: Bool, displayInCat: Bool) {
        guard !selection.isEmpty else { return }
        isCreatingPolicies = true
        creationStatus = "Initialising..."
        deploymentResults = []
        
        // Get all selected items
        let selectedItems = displayItems.filter { selection.contains($0.id) }
        
        Task {
            var results: [OperationResult] = []
            
            for (index, item) in selectedItems.enumerated() {
                await MainActor.run {
                    creationStatus = "Deploying \(index + 1) of \(selectedItems.count)..."
                }
                
                do {
                    // ALL items use Installomator (matched and unmatched both have labels)
                    let appName = item.displayName
                    let label = item.label
                    
                    try await api.createInstallomatorPolicyAsync(
                        appName: appName,
                        label: label,
                        categoryName: category,
                        scriptID: scriptID,
                        featureOnMainPage: featureOnMain,
                        displayInSelfServiceCategory: displayInCat
                    )
                    
                    results.append(OperationResult(
                        itemName: appName,
                        success: true,
                        error: nil
                    ))
                } catch {
                    results.append(OperationResult(
                        itemName: item.displayName,
                        success: false,
                        error: error.localizedDescription
                    ))
                    print("Failed to create policy for \(item.displayName): \(error)")
                }
                
                // THROTTLE: Wait 0.5s between calls
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await MainActor.run {
                isCreatingPolicies = false
                deploymentResults = results
                
                let successCount = results.filter(\.success).count
                let failCount = results.count - successCount
                
                if failCount == 0 {
                    creationStatus = "✓ Completed: \(successCount) created"
                    selection.removeAll()
                    lastSelectedID = nil
                } else {
                    creationStatus = "⚠️ Completed: \(successCount) created, \(failCount) failed"
                }
                
                // Show results sheet
                showResultsSheet = true
                
                // Clear status after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if !isCreatingPolicies {
                        creationStatus = ""
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct CollapsiblePackageSection: View {
    let title: String
    let items: [PackageDisplayItem]
    @Binding var selectedIDs: Set<String>  // Changed from UUID to String
    var onToggle: (String) -> Void  // Changed from UUID to String
    var showAllMode: Bool
    var matcher: PackageMatchingService  // Need access to find matches
    
    @State private var isExpanded = true
    
    var allSelected: Bool {
        items.allSatisfy { selectedIDs.contains($0.id) }
    }
    
    var selectableItems: [PackageDisplayItem] {
        // In "show all" mode, only allow selection of matched items
        if showAllMode {
            return items.filter { $0.isMatched }
        }
        return items
    }
    
    func toggleGroup() {
        if allSelected {
            for item in selectableItems { selectedIDs.remove(item.id) }
        } else {
            for item in selectableItems { selectedIDs.insert(item.id) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Image(systemName: platformIcon)
                            .foregroundColor(.blue)
                        Text(platformTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("(\(items.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                
                if !selectableItems.isEmpty {
                    Button(action: toggleGroup) {
                        Text(allSelected ? "Deselect All" : "Select All")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(10)
            
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        // Use PackageCardView for matched items
                        if item.isMatched, let match = matcher.matches.first(where: { $0.matchedLabel == item.label }) {
                            PackageCardView(match: match)
                                .onTapGesture {
                                    onToggle(item.id)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedIDs.contains(item.id) ? Color.blue : Color.clear, lineWidth: 2)
                                )
                        } else {
                            // Fallback to display item view for unmatched items in "show all" mode
                            PackageDisplayItemView(
                                item: item,
                                isSelected: selectedIDs.contains(item.id),
                                showAllMode: showAllMode
                            )
                            .onTapGesture {
                                onToggle(item.id)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedIDs.contains(item.id) ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .opacity(0.6)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }
    
    var platformIcon: String {
        if title == "macOS" {
            return "applelogo"
        } else if title == "Windows" {
            return "desktopcomputer"
        } else {
            return "tag.fill"
        }
    }
    
    var platformTitle: String {
        if title == "macOS" {
            return "macOS Apps"
        } else if title == "Windows" {
            return "Windows Apps"
        } else {
            return "Unmatched Labels"
        }
    }
}

// MARK: - Helper Component: Import Drop Zone

struct ImportDropZone: View {
    let title: String
    let icon: String
    let acceptedTypes: [UTType]
    let fileName: String?
    let onImport: (URL) -> Void
    
    @State private var isTargeted = false
    @State private var isImporterPresented = false
    
    var body: some View {
        Button(action: { isImporterPresented = true }) {
            VStack(spacing: 15) {
                Image(systemName: fileName == nil ? icon : "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(fileName == nil ? .secondary : .green)
                Text(fileName ?? title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(fileName == nil ? .primary : .green)
                if fileName == nil {
                    Text("Drop File Here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 160, height: 180)
            .background(isTargeted ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isTargeted ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async { onImport(url) }
                }
            }
            return true
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: acceptedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { onImport(url) }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Package Display Item View

struct PackageDisplayItemView: View {
    let item: PackageDisplayItem
    let isSelected: Bool
    let showAllMode: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray.opacity(0.3))
                .font(.title3)
                .opacity((showAllMode && !item.isMatched) ? 0.3 : 1.0)
            
            // Platform icon
            Image(systemName: item.platformIcon)
                .foregroundColor(item.isMatched ? .blue : .gray)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !item.isMatched && showAllMode {
                        Text("• Not matched")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if item.isMatched {
                        Text("• Matched")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1.5)
        )
    }
}
