//
//  PackageCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//


import SwiftUI

struct PackageCardView: View {
    let match: PackageMatch
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 42, height: 42)
                
                Image(systemName: match.platformIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 4) {
                Text(match.intuneApp.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // The Matched Label Badge
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(match.matchedLabel)
                            .font(.caption)
                            .fontDesign(.monospaced)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(4)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(match.intuneApp.platform)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Selection Checkmark
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(.secondary.opacity(0.3))
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.05) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.1), lineWidth: 1)
        )
        // Note: You can use .liquidGlass(.card) here if you have that modifier available globally
    }
}