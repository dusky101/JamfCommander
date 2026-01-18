//
//  ScriptInspectorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//


//
//  ScriptInspectorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct ScriptInspectorView: View {
    let scriptId: Int
    @ObservedObject var api: JamfAPIService
    @Environment(\.dismiss) var dismiss
    
    // We fetch the full record to get the content
    @State private var script: ScriptRecord?
    @State private var isLoading = true
    @State private var selectedTab = 0 // 0 = Info, 1 = Code
    
    var body: some View {
        InspectorShell(
            title: "SCRIPT",
            id: "#\(scriptId)",
            headerText: script?.name ?? "Loading...",
            icon: "terminal.fill",
            isLoading: isLoading,
            onClose: { dismiss() }
        ) {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("View", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Code").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(.ultraThinMaterial)
                
                Divider()
                
                // Content
                if selectedTab == 0 {
                    infoTab
                } else {
                    codeTab
                }
            }
        }
        .task {
            // We reuse the fetchScripts logic or add a specific fetchScript(id:) if needed.
            // Since we don't have a fetchScript(id) in the service yet, we can filter from the main list 
            // OR (Better) just implement a quick fetch detail in the Service if you want strictly detail.
            // For now, let's assume we fetch the list or add a detail fetcher. 
            // *Wait* - The Pro API List endpoint actually returns the script contents if asked! 
            // But usually, it's safer to fetch individual detail. 
            // Let's assume you add a specific fetch function or we filter the list for now.
            // Implementation: We will filter the list for simplicity in this example, 
            // but ideally, you'd add `fetchScriptDetail(id: String)` to the service.
            
            do {
                // Quick fetch logic (you can move this to API service later)
                let allScripts = try await api.fetchScripts()
                if let found = allScripts.first(where: { $0.intId == scriptId }) {
                    self.script = found
                }
                self.isLoading = false
            } catch {
                print("Error loading script: \(error)")
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Tabs
    
    var infoTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // General
                InfoSection(title: "General", icon: "info.circle") {
                    InfoRow(label: "Category", value: script?.categoryName ?? "None")
                    InfoRow(label: "Priority", value: script?.priority ?? "Default")
                    if let notes = script?.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(.caption).foregroundColor(.secondary)
                            Text(notes).font(.body)
                        }
                        .padding(.top, 4)
                    }
                }
                
                // Parameters
                InfoSection(title: "Parameters", icon: "list.number") {
                    if let s = script {
                        if let p4 = s.parameter4, !p4.isEmpty { InfoRow(label: "Param 4", value: p4) }
                        if let p5 = s.parameter5, !p5.isEmpty { InfoRow(label: "Param 5", value: p5) }
                        if let p6 = s.parameter6, !p6.isEmpty { InfoRow(label: "Param 6", value: p6) }
                        if let p7 = s.parameter7, !p7.isEmpty { InfoRow(label: "Param 7", value: p7) }
                        // Add more if needed...
                    } else {
                        Text("No parameters defined.")
                    }
                }
            }
            .padding()
        }
    }
    
    var codeTab: some View {
        ScrollView {
            Text(script?.scriptContents ?? "# No content")
                .font(.system(.body, design: .monospaced)) // Code font
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled) // Allows copying text
        }
        .background(Color.black.opacity(0.8)) // Dark editor look
    }
}