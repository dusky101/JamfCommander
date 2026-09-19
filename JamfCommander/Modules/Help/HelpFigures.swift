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
        "connection-settings",
        "platform-settings",
        "installomator-deploy",
        "version-pinning",
        "package-upload",
        "clone-options",
        "unused-actions",
        "blueprint-editor",
        "computer-inspector",
    ]

    /// Figures drawn straight onto the page, with no card around them.
    ///
    /// The app's own icon is one: a bordered box around it reads as a screenshot of something, when
    /// the point is that this *is* the app. Everything else keeps the card, which is what separates
    /// an illustration from the prose around it.
    static let chromelessIDs: Set<String> = ["app-identity"]

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
        case "connection-settings":
            return "Settings: the instance URL, client ID and client secret, then Initialise Connection."
        case "platform-settings":
            return "The Platform API fields for Blueprints: region, environment ID, client ID and secret, and Test Connection."
        case "installomator-deploy":
            return "The deployment sheet's six numbered steps: category, script, name template, Self Service, scope and version pinning."
        case "version-pinning":
            return "Version pinning: the versions field, the override rows, the policies it will create, and the warning."
        case "package-upload":
            return "The three steps of a package upload: the package record, the file, and the install policy."
        case "clone-options":
            return "The clone options: strip scope, strip triggers, set frequency, and turn Self Service off."
        case "unused-actions":
            return "The Unused audit's three actions, ordered by how easily each can be undone."
        case "blueprint-editor":
            return "The blueprint editor: the JSON, the three scope choices, and the DDM wrap panel."
        case "computer-inspector":
            return "The computer inspector's tabs."
        default:
            return "Illustration"
        }
    }
}

/// Draws the figure with the given id, inside the standard figure frame.
struct HelpFigureView: View {
    let id: String

    var body: some View {
        if HelpFigures.chromelessIDs.contains(id) {
            figure
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HelpFigures.accessibilityLabel(for: id))
        } else {
            HelpFigureCard(accessibilityLabel: HelpFigures.accessibilityLabel(for: id)) {
                figure
            }
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
        case "connection-settings": ConnectionSettingsFigure()
        case "platform-settings": PlatformSettingsFigure()
        case "installomator-deploy": InstallomatorDeployFigure()
        case "version-pinning": VersionPinningFigure()
        case "package-upload": PackageUploadFigure()
        case "clone-options": CloneOptionsFigure()
        case "unused-actions": UnusedActionsFigure()
        case "blueprint-editor": BlueprintEditorFigure()
        case "computer-inspector": ComputerInspectorFigure()
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

// MARK: - Annotation

/// A numbered marker on a figure, matching a **bold reference in the prose** beside it.
///
/// The convention through the guide is that a figure carries markers and the text points at them —
/// "the label goes in **2**" — so a paragraph can name one control out of a dozen without describing
/// where it sits on screen. Labels are short: `1`, `2`, `6a`.
struct FigureMarker: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 18)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: .capsule)
            .accessibilityHidden(true)
    }
}

/// A row of a figure that a marker points at: the marker, then the thing.
struct MarkedRow<Content: View>: View {
    let marker: String
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: 8) {
            FigureMarker(label: marker)
            content
            Spacer(minLength: 0)
        }
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
                .font(.title2)
                .fontWeight(.semibold)

            Text("Two hundred policies, one action.")
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)

            Text(version)
                .font(.caption)
                .foregroundStyle(.tertiary)
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

// MARK: - Workflow figures
//
// These are the figures that explain a *job* rather than name a control: the deployment sheet, the
// upload, version pinning. Each carries `FigureMarker`s, and the prose beside it points at them by
// number, so a paragraph can name one field out of a dozen without describing where it sits.

/// Settings → Jamf Connections, in the order you fill it in.
private struct ConnectionSettingsFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            MarkedRow(marker: "1") { field("Instance URL", "https://yourcompany.jamfcloud.com") }
            MarkedRow(marker: "2") { field("Client ID", "a1b2c3d4-…") }
            MarkedRow(marker: "3") { field("Client Secret", "••••••••••••") }
            MarkedRow(marker: "4") {
                Text("Initialise Connection")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: .capsule)
            }
        }
        .frame(width: 400, alignment: .leading)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 320, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: .rect(cornerRadius: 6))
        }
    }
}

/// The four Platform API fields Blueprints needs, and the button that proves all four at once.
private struct PlatformSettingsFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            MarkedRow(marker: "1") {
                HStack(spacing: 4) {
                    ForEach(PlatformRegion.allCases) { region in
                        Text(region.rawValue)
                            .font(.caption.weight(region == .eu ? .semibold : .regular))
                            .foregroundStyle(region == .eu ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(region == .eu ? Color(nsColor: .windowBackgroundColor) : .clear,
                                        in: .rect(cornerRadius: 5))
                    }
                }
                .padding(2)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 7))
            }
            MarkedRow(marker: "2") { field("Environment ID", "cda24521-f23b-4f27-a9ff-…") }
            MarkedRow(marker: "3") { field("Client ID", "a1b2c3d4-…") }
            MarkedRow(marker: "4") { field("Client Secret", "••••••••••••") }
            MarkedRow(marker: "5") {
                Label("Test Connection", systemImage: "checkmark.seal")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: .capsule)
            }
        }
        .frame(width: 400, alignment: .leading)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(width: 320, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: .rect(cornerRadius: 6))
        }
    }
}

/// The Installomator deployment sheet, numbered as the sheet itself numbers its sections.
///
/// The markers are not invented for the guide: the sheet really is labelled "1. Select Target
/// Category" through "6. Version Pinning", so a reader can match the figure to what is in front of
/// them without translating.
private struct InstallomatorDeployFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            step("1", "Select Target Category", "Communication Apps", "folder")
            step("2", "Select Installomator Script", "Installomator", AppModule.scripts.icon)
            step("3", "Policy Name Template", "Install {appName}", "textformat")
            step("4", "Self Service Options", "Display in category · No icon", "square.grid.2x2")
            step("5", "Deployment Scope", "All Computers", "target")
            step("6", "Version Pinning (Advanced)", "Let Installomator decide", "arrow.triangle.branch")

            Divider().padding(.vertical, 2)

            HStack {
                Text("1 label selected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Deploy Policies")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: .capsule)
            }
        }
        .frame(width: 420, alignment: .leading)
    }

    private func step(_ marker: String, _ title: String, _ value: String, _ symbol: String) -> some View {
        MarkedRow(marker: marker, alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(AppModule.installomator.accentColour)
                    Text(value).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Version pinning, broken into the four things step 6 actually contains.
private struct VersionPinningFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkedRow(marker: "6a", alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versions — one policy is created for each")
                        .font(.caption.weight(.semibold))
                    Text("3.11.9, 3.12.7, 3.13.1")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .frame(width: 300, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7),
                                    in: .rect(cornerRadius: 6))
                }
            }
            MarkedRow(marker: "6b", alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overrides — use {version} where the version appears")
                        .font(.caption.weight(.semibold))
                    HStack(spacing: 6) {
                        Text("downloadURL").font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.7),
                                        in: .rect(cornerRadius: 5))
                        Text("…/app-{version}.dmg").font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.7),
                                        in: .rect(cornerRadius: 5))
                    }
                }
            }
            MarkedRow(marker: "6c", alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Will create 3 policies").font(.caption.weight(.semibold))
                    ForEach(["Install 1Password 3.11.9", "Install 1Password 3.12.7",
                             "Install 1Password 3.13.1"], id: \.self) { name in
                        Text(name).font(.caption2).foregroundStyle(AppModule.computers.accentColour)
                    }
                }
            }
            MarkedRow(marker: "6d", alignment: .top) {
                Label {
                    Text("A pinned download URL stops working the moment the vendor moves the file.")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                }
                .foregroundStyle(.orange)
                .padding(8)
                .frame(width: 320, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 7))
            }
        }
        .frame(width: 420, alignment: .leading)
    }
}

/// The three steps an upload runs, and the fact that each is reported on its own.
private struct PackageUploadFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            step("1", "Create the package record", "Name, file name, category, priority", "doc.badge.plus")
            step("2", "Upload the file", "With progress, and a Cancel button", "arrow.up.circle")
            step("3", "Create the install policy", "Created enabled, offered in Self Service", AppModule.policies.icon)
        }
        .frame(width: 380, alignment: .leading)
    }

    private func step(_ marker: String, _ title: String, _ detail: String, _ symbol: String) -> some View {
        MarkedRow(marker: marker, alignment: .top) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(AppModule.packages.accentColour)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// What a clone can be stripped of before it is made.
private struct CloneOptionsFigure: View {
    private let options = [
        ("a", "Remove scope", "The copy reaches nobody until you scope it"),
        ("b", "Remove triggers", "Nothing sets it running on its own"),
        ("c", "Once per computer", "Frequency, regardless of the original's"),
        ("d", "Self Service off", "It does not appear to your users"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Created disabled — always, and not optional")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppModule.policies.accentColour)
                .padding(.bottom, 2)

            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                MarkedRow(marker: option.0) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.caption)
                            .foregroundStyle(AppModule.policies.accentColour)
                        Text(option.1).font(.caption.weight(.medium))
                        Text("— \(option.2)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 420, alignment: .leading)
    }
}

/// The Unused audit's three actions, drawn in the order they can be undone.
private struct UnusedActionsFigure: View {
    private let actions: [(String, String, String, String, Color)] = [
        ("a", "folder", "Move to Category", "Reversible by hand — nothing stops running", .blue),
        ("b", "pause.circle", "Disable", "Policies only. Reversible from Policies", .orange),
        ("c", "trash", "Delete", "Permanent. Confirmed separately", .red),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                MarkedRow(marker: action.0) {
                    HStack(spacing: 9) {
                        Label(action.2, systemImage: action.1)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(action.4)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(action.4.opacity(0.15), in: .capsule)
                            .frame(width: 150, alignment: .leading)
                        Text(action.3).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 440, alignment: .leading)
    }
}

/// The blueprint editor: what you paste, how it is scoped, and the DDM wrap panel.
private struct BlueprintEditorFigure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarkedRow(marker: "1", alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("The definition, as JSON").font(.caption.weight(.semibold))
                    Text("{ \"name\": \"Passcode policy\",\n  \"components\": [ … ] }")
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .frame(width: 300, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7),
                                    in: .rect(cornerRadius: 6))
                }
            }
            MarkedRow(marker: "2", alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scope — three ways").font(.caption.weight(.semibold))
                    ForEach(["Leave the scope in your JSON alone",
                             "Pick device groups from the environment",
                             "Send it unscoped"], id: \.self) { choice in
                        Text("• \(choice)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            MarkedRow(marker: "3", alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DDM Declaration panel").font(.caption.weight(.semibold))
                    Text("Appears when the JSON is a bare payload. Give it a type, press Wrap as Blueprint.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 300, alignment: .leading)
                }
            }
        }
        .frame(width: 420, alignment: .leading)
    }
}

/// The computer inspector's tabs — what the read-only detail view actually holds.
private struct ComputerInspectorFigure: View {
    private let tabs: [(String, String)] = [
        ("desktopcomputer", "Hardware & OS"),
        ("doc.text.fill", "Profiles"),
        ("applescript.fill", "Scripts"),
        ("scroll.fill", "Policies"),
        ("person.crop.circle", "User & Location"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Label(tab.1, systemImage: tab.0)
                    .font(.caption)
                    .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(index == 0
                                ? AppModule.computers.accentColour.opacity(0.18)
                                : Color(nsColor: .controlBackgroundColor).opacity(0.6),
                                in: .capsule)
            }
        }
    }
}
