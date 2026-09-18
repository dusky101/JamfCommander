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
    /// Housekeeping: policies, profiles and packages that look like they do nothing. Deliberately
    /// absent from `navigationModules` — it is pinned above the footer rather than listed with the
    /// day-to-day modules, because it is an audit rather than a place you work.
    case redundant = "Redundant"

    var id: String { rawValue }

    /// The modules listed in the scrolling sidebar list, in order. `redundant` is pinned separately.
    static var navigationModules: [AppModule] {
        allCases.filter { $0 != .redundant }
    }
    
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
        case .redundant: return "archivebox.fill"
        }
    }

    /// The module's colour, matched to its tile on the dashboard so a module is the same colour
    /// wherever you meet it. Scripts is deliberately the same neutral grey as its tile.
    var accentColour: Color {
        switch self {
        case .dashboard: return .moduleNeutral
        case .policies: return .moduleMagenta
        case .profiles: return .moduleAmber
        case .blueprints: return .moduleCyan
        case .computers: return .moduleAzure
        case .installomator: return .moduleSpring
        case .packages: return .moduleViolet
        case .scripts: return .moduleLime
        case .redundant: return .moduleRose
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

            // Outside the ScrollView on purpose: it stays put above the footer instead of scrolling
            // away with the modules, which is what "set apart from the others" has to mean in a
            // sidebar whose list can overflow.
            moduleButton(for: .redundant)
                .padding(.bottom, 8)

            Divider()

            footer
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var moduleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main Navigation
            ForEach(AppModule.navigationModules) { module in
                moduleButton(for: module)
            }
        }
        .padding(.vertical)
    }

    /// One sidebar entry. Shared by the scrolling list and the pinned Redundant entry so the two
    /// cannot drift apart in appearance or behaviour.
    private func moduleButton(for module: AppModule) -> some View {
        SidebarModuleRow(
            module: module,
            isSelected: currentModule == module,
            action: { currentModule = module }
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarFooterRow(
                title: "Settings",
                icon: "gearshape",
                help: "Jamf Pro and Platform API credentials",
                action: { showConfigSheet = true }
            )

            SidebarFooterRow(
                title: "Help",
                icon: "questionmark.circle",
                help: "Jamf API setup, the Installomator prerequisite, and what each section does",
                action: { HelpPresenter.shared.isPresented = true }
            )
        }
        .padding(.top, 4)
    }
}

/// Settings and Help.
///
/// They behave like the module rows above them — they light up under the pointer and show the link
/// cursor — but stay colourless, because neither is a place in the module list and giving them a hue
/// would put them in competition with it.
private struct SidebarFooterRow: View {
    let title: String
    let icon: String
    let help: String
    var action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 24)

                Text(title)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .offset(x: isHovering && !reduceMotion ? 3 : 0)
        .animation(.snappy(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(title)
    }
}


/// A single sidebar entry.
///
/// Its own view because it owns hover state, and because the whole row — icon, label, background and
/// outline — moves together in the module's own colour. Selection and hover are told apart by weight
/// rather than by colour alone: selected is a stronger fill plus an outline, hover is a light wash.
private struct SidebarModuleRow: View {
    let module: AppModule
    let isSelected: Bool
    var action: () -> Void

    @State private var isHovering = false
    /// Bumped on every press, purely to drive the icon's bounce.
    @State private var pressCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHighlighted: Bool { isSelected || isHovering }

    var body: some View {
        Button {
            pressCount += 1
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: module.icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundStyle(isHighlighted ? module.accentColour : Color.secondary)
                    // Holding the value still under Reduce Motion means the effect simply never
                    // fires, rather than firing and being suppressed.
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : pressCount)

                Text(module.rawValue)
                    .fontWeight(.medium)
                    .foregroundStyle(isHighlighted ? module.accentColour : Color.primary)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(module.accentColour.opacity(isSelected ? 0.18 : (isHovering ? 0.10 : 0)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(module.accentColour.opacity(isSelected ? 0.45 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        // A nudge rather than a scale: scaling a row this small softens its text.
        .offset(x: isHovering && !reduceMotion ? 3 : 0)
        .animation(.snappy(duration: 0.18), value: isHovering)
        .animation(.snappy(duration: 0.22), value: isSelected)
        .onHover { isHovering = $0 }
        // The label is an Image plus a Text inside an HStack, which exposes no accessibility name on
        // its own — VoiceOver read nothing for any of these.
        .accessibilityLabel(module.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
