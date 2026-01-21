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
    @State private var selection = Set<UUID>()
    @State private var searchText = ""
    @State private var selectedPlatformFilter: String = "All"
    
    // Action States
    @State private var creationStatus: String = ""
    @State private var isCreatingPolicies = false
    // Removed cancellables as we are using async/await now
    
    // Config Sheet State
    @State private var showConfigSheet = false
    @State private var animateImportIcon = false
    
    // MARK: - Computed Logic
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
                        ForEach(groupedMatches, id: \.key) { group in
                            CollapsiblePackageSection(
                                title: group.key,
                                matches: group.value,
                                selectedIDs: $selection,
                                onToggle: toggleSelection
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
    }
    
    // MARK: - Components
    var headerView: some View {
        HStack {
            Text("Package Migration Assistant")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            if !matcher.matches.isEmpty {
                Button(action: { matcher.reset() }) {
                    Label("New Session", systemImage: "trash")
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    var filterBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search apps or labels...", text: $searchText).textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            Picker("", selection: $selectedPlatformFilter) {
                Text("All Platforms").tag("All")
                Text("macOS").tag("macOS")
                Text("Windows").tag("Windows")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding(10)
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
                    Text("Analyze Matches")
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
    
    func toggleSelection(id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    
    // UPDATED: Async implementation with throttling
    func deployPolicies(category: String, scriptID: String, featureOnMain: Bool, displayInCat: Bool) {
        guard !selection.isEmpty else { return }
        isCreatingPolicies = true
        creationStatus = "Initialising..."
        
        let selectedMatches = matcher.matches.filter { selection.contains($0.id) }
        
        Task {
            var successCount = 0
            var failCount = 0
            
            for (index, match) in selectedMatches.enumerated() {
                // Update status
                await MainActor.run {
                    creationStatus = "Deploying \(index + 1) of \(selectedMatches.count)..."
                }
                
                do {
                    try await api.createInstallomatorPolicyAsync(
                        appName: match.intuneApp.name,
                        label: match.matchedLabel,
                        categoryName: category,
                        scriptID: scriptID,
                        featureOnMainPage: featureOnMain,
                        displayInSelfServiceCategory: displayInCat
                    )
                    successCount += 1
                } catch {
                    print("Failed to create policy for \(match.intuneApp.name): \(error)")
                    failCount += 1
                }
                
                // THROTTLE: Wait 0.5s between calls to avoid server overwhelm
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await MainActor.run {
                isCreatingPolicies = false
                creationStatus = "Completed: \(successCount) created, \(failCount) failed."
                if failCount == 0 { selection.removeAll() }
            }
        }
    }
}

// MARK: - Subviews

struct CollapsiblePackageSection: View {
    let title: String
    let matches: [PackageMatch]
    @Binding var selectedIDs: Set<UUID>
    var onToggle: (UUID) -> Void
    
    @State private var isExpanded = true
    
    var allSelected: Bool {
        matches.allSatisfy { selectedIDs.contains($0.id) }
    }
    
    func toggleGroup() {
        if allSelected {
            for match in matches { selectedIDs.remove(match.id) }
        } else {
            for match in matches { selectedIDs.insert(match.id) }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Image(systemName: title.lowercased().contains("mac") ? "applelogo" : "desktopcomputer")
                            .foregroundColor(.blue)
                        Text(title == "macOS" ? "macOS Apps" : "Windows Apps")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("(\(matches.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: toggleGroup) {
                    Text(allSelected ? "Deselect All" : "Select All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(10)
            
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(matches) { match in
                        PackageCardView(
                            match: match,
                            isSelected: selectedIDs.contains(match.id)
                        )
                        .onTapGesture { onToggle(match.id) }
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
