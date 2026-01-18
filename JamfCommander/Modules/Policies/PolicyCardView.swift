//
//  PolicyCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//


import SwiftUI

struct PolicyCardView: View {
    let policy: Policy
    let categoryName: String
    
    var computedStatus: JamfItemStatus {
        return policy.enabled ? .active : .inactive
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 42, height: 42)
                
                Image(systemName: "scroll.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.purple)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 4) {
                Text(policy.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text("ID: \(policy.id)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Label(categoryName, systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .liquidGlass(.card)
    }
}
