//
//  InspectorShell.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct InspectorShell<Content: View>: View {
    // Header Data
    let title: String       // e.g., "DEVICE" or "PROFILE"
    let id: String?         // e.g., "#4" (Optional, in case it's new)
    let headerText: String  // e.g., "MacBook Pro" or "Google Chrome"
    let icon: String?       // Optional icon next to the title
    
    // State
    let isLoading: Bool
    var onClose: () -> Void
    
    // The main content of the inspector
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            // --- STANDARD HEADER ---
            VStack(spacing: 12) {
                // Top Bar
                ZStack {
                    // Left: Label & ID
                    HStack {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                if let icon = icon {
                                    Image(systemName: icon)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(title)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let id = id {
                                Text(id)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    
                    // Center: Object Name
                    Text(headerText)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 250)
                    
                    // Right: Close Button
                    HStack {
                        Spacer()
                        Button("Close") { onClose() }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.cancelAction) // Allows Esc key to close
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- CONTENT AREA ---
            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else {
                content() // Inject the specific view here
            }
        }
        .frame(width: 500, height: 650)
        .liquidGlass(.panel)
    }
}