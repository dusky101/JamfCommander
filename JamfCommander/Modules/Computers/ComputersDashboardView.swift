//
//  ComputersDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ComputersDashboardView: View {
    @ObservedObject var api: JamfAPIService
    
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var inspectorSelection: InspectorSelection?
    
    // Filter State
    @State private var showManagedOnly = false
    
    var filteredComputers: [ComputerInventoryRecord] {
        computers.filter { computer in
            let name = computer.general?.name ?? ""
            let serial = computer.hardware?.serialNumber ?? ""
            
            let matchesText = searchText.isEmpty ||
                name.localizedCaseInsensitiveContains(searchText) ||
                serial.localizedCaseInsensitiveContains(searchText)
            
            let isManaged = computer.general?.remoteManagement?.managed ?? false
            let matchesStatus = !showManagedOnly || isManaged
            
            return matchesText && matchesStatus
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Search & Filter Bar ---
            VStack(spacing: 12) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search devices by name or serial...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                
                // Filter Chips
                HStack {
                    // All Devices Chip
                    FilterChip(
                        title: "All Devices",
                        icon: "desktopcomputer.and.macbook", // Specific Icon
                        selectedIcon: "desktopcomputer.and.macbook", // Prevent auto-.fill
                        color: .blue,
                        isSelected: !showManagedOnly,
                        count: computers.count
                    ) { showManagedOnly = false }
                    
                    // Managed Only Chip
                    FilterChip(
                        title: "Managed Only",
                        icon: "checkmark.seal",
                        selectedIcon: "checkmark.seal.fill",
                        color: .green,
                        isSelected: showManagedOnly,
                        count: computers.filter { $0.general?.remoteManagement?.managed ?? false }.count
                    ) { showManagedOnly = true }
                    
                    Spacer()
                }
            }
            .padding()
            .overlay(Divider().opacity(0.5), alignment: .bottom)
            .zIndex(1)
            
            // --- Main List ---
            if isLoading {
                ProgressView("Scanning Fleet (Pro API)...")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredComputers) { computer in
                            ComputerCardView(computer: computer)
                                .onTapGesture {
                                    inspectorSelection = InspectorSelection(id: computer.intId)
                                }
                                .contextMenu {
                                    Button("Inspect") { inspectorSelection = InspectorSelection(id: computer.intId) }
                                    Divider()
                                    if let serial = computer.hardware?.serialNumber {
                                        Button("Copy Serial: \(serial)") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(serial, forType: .string)
                                        }
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.clear)
        .task {
            await loadComputers()
        }
        // FIX: Removed 'self.' to fix the wrapper error
        .sheet(item: $inspectorSelection) { selection in
            ComputerInspectorView(computerId: selection.id, api: api)
        }
    }
    
    func loadComputers() async {
        do {
            let list = try await api.fetchComputers()
            self.computers = list
            self.isLoading = false
        } catch {
            print("Error loading computers: \(error)")
            self.isLoading = false
        }
    }
}


