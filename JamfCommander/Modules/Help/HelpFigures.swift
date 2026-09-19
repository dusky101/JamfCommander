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
        "dashboard-tiles",
        "bulk-actions",
        "status-badges",
        "blueprint-row",
        "computer-row",
        "package-tabs",
        "script-parameters",
        "label-states",
        "unused-reasons",
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
        case "dashboard-tiles":
            return "Dashboard tiles: a count, a tile still loading, and one showing a dash because it could not be read."
        case "bulk-actions":
            return "The bulk action panel that replaces the filter bar when rows are selected."
        case "status-badges":
            return "The Scoped and Unscoped badges, each with its own symbol as well as its own colour."
        case "blueprint-row":
            return "A blueprint row, with the deployment state the server reports."
        case "computer-row":
            return "A computer row: name, serial number and assigned user."
        case "package-tabs":
            return "The Packages tabs — New, Uploaded and Deployed — with a row still being checked."
        case "script-parameters":
            return "Script parameter labels four to eleven, as Installomator expects them."
        case "label-states":
            return "The four Installomator views, and a row flagged Missing."
        case "unused-reasons":
            return "The Unused audit's reason filters, one per reason a row can be listed."
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
        case "dashboard-tiles": DashboardTilesFigure()
        case "bulk-actions": BulkActionsFigure()
        case "status-badges": StatusBadgesFigure()
        case "blueprint-row": BlueprintRowFigure()
        case "computer-row": ComputerRowFigure()
        case "package-tabs": PackageTabsFigure()
        case "script-parameters": ScriptParametersFigure()
        case "label-states": LabelStatesFigure()
        case "unused-reasons": UnusedReasonsFigure()
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

// MARK: - Module figures

/// Three Dashboard tiles, showing the three things a tile can say.
///
/// Colours and symbols come from `AppModule`, so they are the tiles you actually have.
private struct DashboardTilesFigure: View {
    var body: some View {
        HStack(spacing: 12) {
            tile(.policies, value: .init(text: "249"))
            tile(.redundant, value: .init(text: "14", isCounting: true))
            tile(.blueprints, value: .init(text: "—", isDimmed: true))
        }
    }

    private struct Value {
        var text: String
        var isCounting = false
        var isDimmed = false
    }

    private func tile(_ module: AppModule, value: Value) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(module.accentColour.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: module.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(module.accentColour)
                }
                Spacer(minLength: 0)
                if value.isCounting {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 11, height: 11)
                }
                Text(value.text)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(value.isDimmed ? Color.secondary : Color.primary)
            }
            Text(module.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(width: 132, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// The bulk action panel that replaces the filter bar the moment anything is selected.
private struct BulkActionsFigure: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("3 selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            action("Move Category", "folder", .blue)
            action("Scope", "target", .purple)
            action("Clone", "doc.on.doc", .teal)
            // Delete is the only one that is not reversible, and it is drawn that way.
            action("Delete", "trash", .red)
        }
        .padding(9)
        .background(.bar, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func action(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

/// The two badges a profile or policy row can carry, from `JamfItemStatus` itself.
///
/// Both cases are drawn, side by side, because the point is that they differ by **symbol** as well
/// as colour — nothing in this app tells you something by colour alone.
private struct StatusBadgesFigure: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([JamfItemStatus.active, .inactive]) { status in
                Label(status.rawValue, systemImage: status.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(status.color.opacity(0.15), in: .capsule)
            }
        }
    }
}

/// A blueprint row, with the deployment state the server reports rather than one the app assumed.
private struct BlueprintRowFigure: View {
    var body: some View {
        VStack(spacing: 6) {
            row(name: "Passcode policy", state: "Deployed", tint: .green)
            row(name: "Extensible SSO", state: "Not Deployed", tint: .secondary)
        }
        .frame(width: 320)
    }

    private func row(name: String, state: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: AppModule.blueprints.icon)
                .font(.caption)
                .foregroundStyle(AppModule.blueprints.accentColour)
            Text(name).font(.callout)
            Spacer(minLength: 0)
            Text(state)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.15), in: .capsule)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 8))
    }
}

/// A computer row — what you can search on, shown as what you would search for.
private struct ComputerRowFigure: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: AppModule.computers.icon)
                .font(.callout)
                .foregroundStyle(AppModule.computers.accentColour)
            VStack(alignment: .leading, spacing: 2) {
                Text("MAC-C02DR4J3Q6LT").font(.callout)
                Text("C02DR4J3Q6LT · a.admin@yourcompany.co.uk")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Label("Active", systemImage: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// The three Packages tabs, and a row still being checked.
private struct PackageTabsFigure: View {
    private let tabs = ["New", "Uploaded", "Deployed"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Text(tab)
                        .font(.caption.weight(index == 1 ? .semibold : .regular))
                        .foregroundStyle(index == 1 ? Color.primary : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background {
                            if index == 1 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                }
            }
            .padding(2)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))

            HStack(spacing: 10) {
                Image(systemName: AppModule.packages.icon)
                    .font(.caption)
                    .foregroundStyle(AppModule.packages.accentColour)
                Text("SomeTool-2.4.pkg").font(.callout)
                Spacer(minLength: 0)
                // The honest state while the estate scan runs — never "unused".
                Text("Checking…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 300)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 8))
        }
    }
}

/// Script parameter labels, as the Installomator module expects to find them.
private struct ScriptParametersFigure: View {
    private let rows: [(String, String)] = [
        ("Parameter 4", "Label"),
        ("Parameter 5", "Option"),
        ("Parameter 6", "Option"),
        ("Parameters 7–11", "Override"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(row.1)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppModule.scripts.accentColour.opacity(0.15), in: .rect(cornerRadius: 5))
                }
            }
        }
        .frame(width: 260, alignment: .leading)
    }
}

/// The four Installomator views, from `PackageViewMode` itself, and a row flagged Missing.
private struct LabelStatesFigure: View {
    private let selected: PackageViewMode = .missing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(PackageViewMode.allCases) { mode in
                    Text(mode.rawValue)
                        .font(.caption)
                        .foregroundStyle(mode == selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            AppModule.installomator.accentColour
                                .opacity(mode == selected ? 0.20 : 0.06),
                            in: .capsule
                        )
                }
            }

            HStack(spacing: 10) {
                Image(systemName: AppModule.installomator.icon)
                    .font(.caption)
                    .foregroundStyle(AppModule.installomator.accentColour)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adobe Acrobat Reader").font(.callout)
                    Text("Not in the Installomator label list")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Text("Missing")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.16), in: .capsule)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6), in: .rect(cornerRadius: 8))
        }
        .frame(width: 360, alignment: .leading)
    }
}

/// Every reason a row can be listed in the Unused audit, straight from `RedundantReason`.
///
/// Iterating `allCases` means a new reason appears here the day it is added, with its own symbol and
/// colour, and the explanation under each is the enum's own `explanation` — the same words the audit
/// puts on the row.
private struct UnusedReasonsFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(RedundantReason.allCases) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(reason.rawValue, systemImage: reason.icon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(reason.colour)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(reason.colour.opacity(0.15), in: .capsule)
                        .frame(width: 130, alignment: .leading)

                    Text(reason.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: 420, alignment: .leading)
    }
}
