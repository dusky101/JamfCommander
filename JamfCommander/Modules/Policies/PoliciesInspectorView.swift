//
//  PoliciesInspectorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//


import SwiftUI

struct PoliciesInspectorView: View {
    let policyId: Int
    @ObservedObject var api: JamfAPIService
    @Environment(\.dismiss) var dismiss
    
    // Data State
    @State private var jsonContent: String = "Loading..."
    @State private var policyDetail: PolicyDetailXML?
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Edit State
    @State private var isEditingScope = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            ZStack {
                // Left
                HStack {
                    VStack(alignment: .leading) {
                        Text("Inspector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "scroll.fill")
                                .font(.caption2)
                            Text("ID: \(policyId)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // Center
                Text(policyDetail?.general.name ?? "Loading...")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
                
                // Right
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView().controlSize(.small).padding(.trailing, 8)
                    }
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- CONTENT ---
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Fetching Policy Data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                HSplitView {
                    // LEFT: Info & Scope
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                scopeSection
                            }
                            .padding()
                        }
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.02))
                    
                    // RIGHT: JSON Source
                    JSONEditorView(
                        title: "Raw Source (JSON)",
                        text: $jsonContent,
                        onSave: { _ in isSaving = false } // Mock save
                    )
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
            }
        }
        .frame(width: 950, height: 700)
        .liquidGlass(.panel)
        .task {
            await loadData()
        }
    }
    
    var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Deployment Scope", systemImage: "scope")
                .font(.headline)
            
            if let scope = policyDetail?.scope {
                if scope.all_computers {
                    scopeBadge(title: "All Computers", subtitle: "Runs on fleet.", icon: "globe", color: .green)
                } else {
                    scopeBadge(title: "Targeted", subtitle: "Restricted scope.", icon: "target", color: .orange)
                }
                
                if !scope.all_computers, let computers = scope.computers {
                    Text("TARGETS (\(computers.count))")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary).padding(.top, 8)
                    ForEach(computers) { computer in
                        HStack {
                            Image(systemName: "desktopcomputer").foregroundColor(.secondary)
                            Text(computer.name).font(.subheadline)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    func scopeBadge(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).padding(.trailing, 4)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).opacity(0.8)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    func loadData() async {
        do {
            async let fetchedJSON = api.fetchPolicyJSON(id: policyId)
            async let fetchedDetail = api.fetchPolicyDetail(id: policyId)
            let (json, detail) = try await (fetchedJSON, fetchedDetail)
            self.jsonContent = json
            self.policyDetail = detail
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}
