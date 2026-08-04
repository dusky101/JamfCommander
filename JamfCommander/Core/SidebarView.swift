//
//  SidebarView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

enum AppModule: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case policies = "Policies"
    case profiles = "Profiles"
    case computers = "Computers"
    case packages = "Packages" // Added Packages
    case scripts = "Scripts"

    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .profiles: return "doc.text.fill"
        case .computers: return "desktopcomputer"
        case .scripts: return "applescript.fill"
        case .policies: return "scroll.fill"
        case .packages: return "shippingbox.fill" // Icon for Packages
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
            
            // Settings & Help
            Button(action: { showConfigSheet = true }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .padding(10)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { HelpPresenter.shared.isPresented = true }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("Help")
                }
                .padding(10)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Jamf API setup, the Installomator prerequisite, and what each section does")
        }
        .padding()
    }
}
