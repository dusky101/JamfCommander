//
//  ScriptsDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct ScriptsDashboardView: View {
    @ObservedObject var api: JamfAPIService
    
    @State private var scripts: [ScriptRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var inspectorSelection: InspectorSelection?
    
    var groupedScripts: [(key: String, value: [ScriptRecord])] {
        let filtered = scripts.filter { script in
            searchText.isEmpty ||
            script.name.localizedCaseInsensitiveContains(searchText)
        }
        let grouped = Dictionary(grouping: filtered) { $0.safeCategory }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search scripts...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .overlay(Divider(), alignment: .bottom)
            
            // Content
            if isLoading {
                ProgressView("Loading Scripts...")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedScripts, id: \.key) { group in
                            ScriptCategorySection(
                                title: group.key,
                                scripts: group.value,
                                onInspect: { id in
                                    inspectorSelection = InspectorSelection(id: id)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            do {
                self.scripts = try await api.fetchScripts()
                self.isLoading = false
            } catch {
                print("Error fetching scripts: \(error)")
                self.isLoading = false
            }
        }
        .sheet(item: $inspectorSelection) { selection in
            ScriptInspectorView(scriptId: selection.id, api: api)
        }
    }
}

// Local Section Component
struct ScriptCategorySection: View {
    let title: String
    let scripts: [ScriptRecord]
    var onInspect: (Int) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(title).font(.headline)
                    Spacer()
                    Text("\(scripts.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(10)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // List
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(scripts) { script in
                        // FIX: Pass osRequirements here
                        ScriptCardView(
                            script: script,
                            categoryName: title,
                            osRequirements: script.osRequirements ?? "Any"
                        )
                        .onTapGesture {
                            onInspect(script.intId)
                        }
                        .contextMenu {
                            Button("Inspect") { onInspect(script.intId) }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
    }
}
