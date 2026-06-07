//
//  StatusBadge.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct StatusBadge: View {
    let status: JamfItemStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
                .fontWeight(.bold)
            
            Text(status.rawValue)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(status.color)
        .background(status.color.opacity(0.1)) // Subtle background tint
        .cornerRadius(8)
        .overlay(
            // The "Glassy" border stroke
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.color.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    HStack {
        StatusBadge(status: .active)
        StatusBadge(status: .failed)
        StatusBadge(status: .pending)
    }
    .padding()
}
