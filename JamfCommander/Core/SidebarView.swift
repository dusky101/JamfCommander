//
//  SidebarView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

enum AppModule: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case profiles = "Profiles"
    case computers = "Computers"
    case scripts = "Scripts" // Added Scripts
    case policies = "Policies"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .profiles: return "doc.text.fill"
        case .computers: return "desktopcomputer"
        case .scripts: return "applescript.fill" // Requested icon
        case .policies: return "scroll.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var currentModule: AppModule
    @Binding var showConfigSheet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main Navigation
            ForEach(AppModule.allCases) { module in
                Button(action: { currentModule = module }) {
                    HStack(spacing: 12) {
                        Image(systemName: module.icon)
                            .font(.system(size: 16))
                            .frame(width: 24)
                        
                        Text(module.rawValue)
                            .fontWeight(.medium)
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(currentModule == module ? Color.blue.opacity(0.15) : Color.clear)
                    .foregroundColor(currentModule == module ? .blue : .primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Divider()
            
            // Settings Button
            Button(action: { showConfigSheet = true }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .padding(10)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}
