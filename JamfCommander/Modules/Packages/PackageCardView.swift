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
                    
                    // The version this policy pins. Several deployed rows can share a label — one per
                    // pinned version — so this is what tells them apart at a glance.
                    if let pinnedVersion = item.pinnedVersion {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                            Text(pinnedVersion)
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                        .accessibilityLabel("Pinned to version \(pinnedVersion)")
                    }

                    // Something in Jamf already looks like this app, but it isn't a recognised
                    // Installomator policy — surface the name so the cause is obvious.
                    if let existingPolicyName = item.existingPolicyName {
                        Label("Matches '\(existingPolicyName)'", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }

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
        .contentShape(Rectangle())
    }
}