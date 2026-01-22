//
//  ProfileCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ProfileCardView: View {
    let profile: ConfigProfile
    let categoryName: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 42, height: 42)
                
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            // Text Details
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text("ID: \(profile.id)")
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
            
            // Status Badge (Right aligned) - Now using actual status from profile
            StatusBadge(status: profile.status)
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        // Apply our custom card style
        .liquidGlass(.card)
    }
}
