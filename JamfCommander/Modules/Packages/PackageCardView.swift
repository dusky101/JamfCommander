//
//  PackageCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//


import SwiftUI

struct PackageCardView: View {
    let item: InstallomatorItem
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Status icon
            ZStack {
                Circle()
                    .fill(item.statusColor.opacity(0.1))
                    .frame(width: 42, height: 42)
                
                Image(systemName: item.statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(item.statusColor)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // Label badge
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(item.label)
                            .font(.caption)
                            .fontDesign(.monospaced)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(item.statusColor.opacity(0.1))
                    .foregroundColor(item.statusColor)
                    .cornerRadius(4)
                    
                    // Policy details (deployed items only)
                    if item.isDeployed {
                        if let policyID = item.policyID {
                            Text("ID: \(policyID)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Label(item.safeCategory, systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Status badge
            Text(item.statusText)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.statusColor.opacity(0.15))
                .foregroundColor(item.statusColor)
                .cornerRadius(6)
            
            // Selection indicator (only for available items)
            if !item.isDeployed {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
            }
        }
        .padding(12)
        .liquidGlass(cornerRadius: 12)
    }
}