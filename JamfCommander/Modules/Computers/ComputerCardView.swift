//
//  ComputerCardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct ComputerCardView: View {
    let computer: ComputerInventoryRecord

    /// Build a single-line description of the assigned user for the card.
    /// Returns nil when there's nothing useful to show.
    private var assignedUserLine: String? {
        let displayName = (computer.userAndLocation?.realname?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? (computer.userAndLocation?.username?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 }

        let email = (computer.userAndLocation?.email?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }

        switch (displayName, email) {
        case let (name?, email?):
            return "\(name) • \(email)"
        case let (name?, nil):
            return name
        case let (nil, email?):
            return email
        default:
            return nil
        }
    }

    var body: some View {
        let isManaged = computer.general?.remoteManagement?.managed ?? false
        let model = computer.hardware?.model ?? "Mac"
        
        // Use our new DeviceSymbols helper to get the exact icon
        let iconName = DeviceSymbols.iconName(for: model)
        
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(isManaged ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundColor(isManaged ? .blue : .orange)
            }
            
            // Text Info
            VStack(alignment: .leading, spacing: 4) {
                // ROW 1: Name + ID
                HStack(spacing: 8) {
                    Text(computer.general?.name ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // ID Badge
                    Text("ID: \(computer.id)")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // ROW 2: Model + Serial
                HStack(spacing: 8) {
                    Text(model)
                    if let serial = computer.hardware?.serialNumber {
                        Text("•")
                        Text(serial).fontDesign(.monospaced)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // ROW 3: Assigned user (name and/or email), only when present
                if let userLine = assignedUserLine {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(userLine)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            
            Spacer()
            
            // Status Badge
            if !isManaged {
                Text("Unmanaged")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
            } else {
                 Text("Managed")
                     .font(.caption2)
                     .padding(.horizontal, 8)
                     .padding(.vertical, 4)
                     .background(Color.green.opacity(0.1))
                     .foregroundColor(.green)
                     .cornerRadius(8)
            }
        }
        .padding(12)
        .liquidGlass(cornerRadius: 12)
    }
}
