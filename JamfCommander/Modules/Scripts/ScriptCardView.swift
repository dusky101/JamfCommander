//
//  ScriptCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct ScriptCardView: View {
    let script: ScriptRecord
    let categoryName: String
    let osRequirements: String // New Property
    
    var computedStatus: JamfItemStatus {
        return .active
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 42, height: 42)
                
                Image(systemName: "applescript.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 4) {
                Text(script.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // ID Badge
                    Text("ID: \(script.id)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    // Category Label
                    Label(categoryName, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // OS Requirement Label (Only show if not empty/Any)
                    if osRequirements != "Any" && !osRequirements.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Label("OS: \(osRequirements)", systemImage: "desktopcomputer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Status Badge
            StatusBadge(status: computedStatus)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .liquidGlass(cornerRadius: 12)
    }
}
