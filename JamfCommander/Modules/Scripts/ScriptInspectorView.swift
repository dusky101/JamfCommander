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
    
    // Data State
    @State private var scriptContent: String = "Loading..."
    @State private var scriptDetail: ScriptRecord?
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Edit State
    @State private var isEditingInfo = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            ZStack {
                // 1. Left: ID & Label
                HStack {
                    VStack(alignment: .leading) {
                        Text("Inspector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "applescript.fill")
                                .font(.caption2)
                            Text("ID: \(scriptId)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // 2. Center: Script Name
                Text(scriptDetail?.name ?? "Loading...")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
                
                // 3. Right: Actions
                HStack {
                    Spacer()
                    
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                    
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- MAIN CONTENT ---
            if isLoading {
                loadingView
            } else {
                HSplitView {
                    // LEFT PANE: Info & Parameters (Fixed Width)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                generalInfoSection
                                parametersSection
                            }
                            .padding()
                        }
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.02))
                    
                    // RIGHT PANE: Code Editor (Remaining Width)
                    CodeEditorView(
                        title: "Script Source (Shell/Bash)",
                        text: $scriptContent,
                        onSave: { newCode in
                            saveChanges(newCode)
                        }
                    )
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
            }
            
            // Error Banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
            }
        }
        .frame(width: 950, height: 700)
        .liquidGlass(.panel)
        .task {
            await loadData()
        }
    }
    
    // MARK: - Subviews
    
    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching Script Data...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
    
    var generalInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("General Info", systemImage: "info.circle")
                    .font(.headline)
                Spacer()
                Button(isEditingInfo ? "Done" : "Edit") {
                    withAnimation { isEditingInfo.toggle() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(isEditingInfo ? .blue : .secondary)
            }
            
            if let script = scriptDetail {
                infoRow(label: "Category", value: script.categoryName ?? "None")
                infoRow(label: "Priority", value: script.priority ?? "Default")
                
                if let notes = script.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.caption).foregroundColor(.secondary)
                        Text(notes).font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
    }
    
    var parametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Parameters", systemImage: "list.number")
                .font(.headline)
            
            if let script = scriptDetail {
                // Only show parameters that exist or show empty state
                Group {
                    paramRow(num: 4, value: script.parameter4)
                    paramRow(num: 5, value: script.parameter5)
                    paramRow(num: 6, value: script.parameter6)
                    paramRow(num: 7, value: script.parameter7)
                    // You can add 8-11 here if needed
                }
            }
        }
    }
    
    func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }
    
    func paramRow(num: Int, value: String?) -> some View {
        HStack {
            Text("P\(num)")
                .font(.caption2)
                .fontDesign(.monospaced)
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            
            if let val = value, !val.isEmpty {
                Text(val).font(.caption)
            } else {
                Text("Unused").font(.caption).foregroundColor(.secondary.opacity(0.5)).italic()
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Actions
    
    func loadData() async {
        do {
            // Since we haven't built a specific fetchScript(id) yet, we will filter from list
            // In a real app, you would add `api.fetchScriptDetail(id: Int)`
            let allScripts = try await api.fetchScripts()
            if let found = allScripts.first(where: { $0.intId == scriptId }) {
                self.scriptDetail = found
                self.scriptContent = found.scriptContents ?? "# No content"
            }
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load script."
            self.isLoading = false
        }
    }
    
    func saveChanges(_ newCode: String) {
        isSaving = true
        // Mock save for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
        }
    }
}

// MARK: - Local Code Editor Component
// Mirrors the JSONEditorView but for Shell scripts

struct CodeEditorView: View {
    let title: String
    @Binding var text: String
    var onSave: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(.caption)
                
                Button(action: { onSave(text) }) {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            
            Divider()
            
            // Editor Area
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .padding(4)
                .scrollContentBackground(.hidden) // Removes default white background
                .background(Color(red: 0.1, green: 0.1, blue: 0.1)) // Dark Editor BG
        }
    }
}
