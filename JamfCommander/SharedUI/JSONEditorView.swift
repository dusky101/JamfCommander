//
//  JSONEditorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct JSONEditorView: View {
    let title: String
    @Binding var text: String
    @State private var isEditing = false
    
    // Actions
    var onSave: ((String) -> Void)?
    var onDelete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Toolbar ---
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(isEditing ? "Editing Mode" : "Read-Only Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Copy Button
                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Edit Toggle (Only shows if onSave exists)
                if onSave != nil {
                    Button(action: { isEditing.toggle() }) {
                        Label(isEditing ? "Cancel" : "Edit", systemImage: isEditing ? "xmark" : "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- Editor / Viewer Area ---
            ZStack(alignment: .topTrailing) {
                if isEditing {
                    // Editing Mode: TextEditor
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .foregroundColor(.primary)
                        .padding(4)
                } else {
                    // Read-Only Mode: ScrollView + Text (Fixes scrolling issues)
                    ScrollView {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled) // Allows user to select/copy text
                            .foregroundColor(.secondary)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                }
                
                // Floating Save Button
                if isEditing {
                    Button(action: {
                        onSave?(text)
                        isEditing = false
                    }) {
                        Text("Save Changes")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
            }
            
            // --- Bottom Danger Zone ---
            if let onDelete = onDelete {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Danger Zone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Delete This Item", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                .padding()
                .background(Color.red.opacity(0.05))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
