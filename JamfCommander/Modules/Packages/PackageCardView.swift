//
//  PackageCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//


import SwiftUI

struct PackageCardView: View {
    let match: PackageMatch
    
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
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .liquidGlass(.card)
    }
}