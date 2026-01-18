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
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "terminal") // Script icon
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(script.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("ID: \(script.id)")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Category Badge (optional, useful if viewing 'All')
            Text(categoryName)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}