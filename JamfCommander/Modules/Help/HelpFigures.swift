//
//  HelpFigures.swift
//  JamfCommander
//
//  The live-figure registry.
//
//  This whole app is drawn in code, so the guide draws its illustrations the same way. Each figure is
//  a small, self-contained SwiftUI view built from the app's *own* types and tokens — `AppModule` and
//  its `icon` and `accentColour`, the real SF Symbols, the same glass and gradient. The point is not
//  that it is cheaper than a screenshot. It is that a screenshot goes stale silently: rename a module
//  or change its colour and the picture keeps showing the old one, confidently, until somebody
//  notices. A figure that iterates `AppModule.allCases` cannot.
//
//  A ```figure fence in a topic's Markdown, whose body is an id, resolves to `HelpFigureView(id:)`.
//  The dispatch is a `switch` rather than `AnyView`, so SwiftUI keeps view identity.
//
//  Figures are purely presentational: no service, no network, no interaction. Nothing here may read
//  the tenant — an illustration that showed somebody's real policy names would be a privacy problem
//  and a support problem at once.
//

import SwiftUI

nonisolated enum HelpFigures {

    /// Every figure id the registry can draw. Kept beside the `switch` in `HelpFigureView` so the two
    /// are changed together.
    static let knownIDs: Set<String> = [
        "app-identity",
        "help-index",
        "sidebar",
    ]

    /// What the illustration says, for somebody who cannot see it. A figure is one element to
    /// VoiceOver, so this has to carry the whole point of it rather than name its parts.
    static func accessibilityLabel(for id: String) -> String {
        switch id {
        case "app-identity":
            return "The Jamf Commander icon, name and the version you are running."
        case "help-index":
            return "The guide's index: a search button at the top, then collapsible sections of topics."
        case "sidebar":
            return "The app's sidebar, listing every module in its own colour."
        default:
            return "Illustration"
        }
    }
}

/// Draws the figure with the given id, inside the standard figure frame.
struct HelpFigureView: View {
    let id: String

    var body: some View {
        HelpFigureCard(accessibilityLabel: HelpFigures.accessibilityLabel(for: id)) {
            figure
        }
    }

    @ViewBuilder
    private var figure: some View {
        switch id {
        case "app-identity": AppIdentityFigure()
        case "help-index": HelpIndexFigure()
        case "sidebar": SidebarFigure()
        default: MissingFigure(id: id)
        }
    }
}

/// The frame every figure sits in: inset, bordered, and inert.
struct HelpFigureCard<Content: View>: View {
    var accessibilityLabel: String = "Illustration"
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5),
                        in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            // An illustration is not a control. Clicking one should do nothing rather than something
            // surprising, and it must not be a tab stop.
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}

/// Shown when a figure id has no matching view — visible and honest, rather than a blank space that
/// reads as a layout bug.
struct MissingFigure: View {
    let id: String

    var body: some View {
        Label("Figure “\(id)” is not available.", systemImage: "questionmark.square.dashed")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }
}

// MARK: - Figures

/// The app's own icon, name and version.
///
/// The icon comes from `NSApplication.shared.applicationIconImage` and the version from the bundle,
/// so this is the icon and the number you are actually running — not a copy of either.
private struct AppIdentityFigure: View {
    private var appIcon: NSImage { NSApplication.shared.applicationIconImage ?? NSImage() }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        guard let build, build != short else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Jamf Commander")
                .font(.title3)
                .fontWeight(.semibold)

            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// The sidebar, drawn from `AppModule` itself.
///
/// It iterates `AppModule.navigationModules` and the two pinned modules, and takes each row's symbol
/// and colour from the enum, so adding a module or changing its colour updates this picture without
/// anyone remembering to.
private struct SidebarFigure: View {
    private let selected: AppModule = .policies

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AppModule.navigationModules) { module in
                row(module)
            }
            Divider().padding(.vertical, 4)
            row(.installomator)
            row(.redundant)
        }
        .padding(8)
        .frame(width: 210)
        .background(.bar, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func row(_ module: AppModule) -> some View {
        let isSelected = module == selected
        return HStack(spacing: 10) {
            Image(systemName: module.icon)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(isSelected ? module.accentColour : Color.secondary)
            Text(module.rawValue)
                .font(.callout)
                .foregroundStyle(isSelected ? module.accentColour : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(module.accentColour.opacity(isSelected ? 0.18 : 0))
        }
    }
}

/// The guide's own index: the search button, then a collapsed section and an open one.
///
/// Self-referential on purpose — it is the fastest way to explain a search box that is a button
/// rather than a field, which is not what anybody expects.
private struct HelpIndexFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search the guide")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("⌘F")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            sectionHeader(.gettingStarted, isOpen: true)
            topic("Welcome to Jamf Commander", isSelected: true)
            topic("Prerequisites", isSelected: false)

            sectionHeader(.modules, isOpen: false)
            sectionHeader(.reference, isOpen: false)
        }
        .frame(width: 240)
    }

    private func sectionHeader(_ section: HelpSection, isOpen: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Image(systemName: section.systemImage)
                .font(.caption)
                .foregroundStyle(section.colour)
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(section.colour)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func topic(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.callout)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.22 : 0))
            }
            .padding(.leading, 16)
    }
}
