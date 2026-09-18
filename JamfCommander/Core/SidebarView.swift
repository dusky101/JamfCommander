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
    /// Declarative device management blueprints. Served by the Platform API Gateway, which uses
    /// its own credentials — see PlatformAPISession.
    case blueprints = "Blueprints"
    case computers = "Computers"
    /// Install policies driven by the Installomator script — discovery, deployment and editing.
    case installomator = "Installomator"
    /// Jamf's own package library: the packages already held, and uploading one the administrator
    /// supplies for software Installomator has no label for.
    case packages = "Packages"
    case scripts = "Scripts"

    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .profiles: return "doc.text.fill"
        case .blueprints: return "square.stack.3d.up.fill"
        case .computers: return "desktopcomputer"
        case .scripts: return "applescript.fill"
        case .policies: return "scroll.fill"
        case .installomator: return "arrow.down.app.fill"
        case .packages: return "shippingbox.fill"
        }
    }
}

struct SidebarView: View {
    @Binding var currentModule: AppModule
    @Binding var showConfigSheet: Bool
    
    var body: some View {
        // The module list scrolls and the footer stays pinned. As one plain VStack the whole
        // sidebar overflowed a short window and was clipped at BOTH ends — items disappeared under
        // the traffic lights while Settings and Help fell off the bottom.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                moduleList
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            footer
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var moduleList: some View {
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
                // The label is an Image plus a Text inside an HStack, which exposes no
                // accessibility name on its own — VoiceOver read nothing for any of these.
                .accessibilityLabel(module.rawValue)
                .accessibilityAddTraits(currentModule == module ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .padding(.top, 4)
    }
}
