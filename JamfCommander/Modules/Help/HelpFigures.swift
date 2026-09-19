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
        "policy-row",
        "profile-row",
        "status-badges",
        "bulk-actions",
        "single-action-bar",
        "blueprint-row",
        "package-row",
        "label-states",
        "unused-rows",
        "unused-actions",
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
            return "Dashboard tiles: a count, one still counting, and one showing a dash because it could not be read."
        case "policy-row":
            return "A policy row: its icon, name, ID, category and status badge."
        case "profile-row":
            return "Two profile rows, one scoped and one unscoped."
        case "status-badges":
            return "The Scoped and Unscoped badges, each with its own symbol as well as its own colour."
        case "bulk-actions":
            return "The bulk action panel that replaces the filter bar when several rows are selected."
        case "single-action-bar":
            return "The action bar for one selected policy, named for that policy rather than a count."
        case "blueprint-row":
            return "Blueprint rows, with the deployment state the server reports."
        case "package-row":
            return "A package row from Jamf's library."
        case "label-states":
            return "The four Installomator views, and rows in the deployed, available and missing states."
        case "unused-rows":
            return "Unused audit rows, each showing the reason it was listed."
        case "unused-actions":
            return "The Unused audit's action bar, its columns ordered by how easily each undoes."
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
        case "policy-row": PolicyRowFigure()
        case "profile-row": ProfileRowFigure()
        case "status-badges": StatusBadgesFigure()
        case "bulk-actions": BulkActionsFigure()
        case "single-action-bar": SingleActionBarFigure()
        case "blueprint-row": BlueprintRowFigure()
        case "package-row": PackageRowFigure()
        case "label-states": LabelStatesFigure()
        case "unused-rows": UnusedRowsFigure()
        case "unused-actions": UnusedActionsFigure()
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


/// The bulk action panel, built from the **real** components.
///
/// `ActionBarColumn`, `SoftIconLabel` and `.appBarBackground()` are the same types
/// `ActionPanelView` uses, and the tints are the ones it passes. That is the difference between a
/// figure and a drawing: the first version of this was drawn by hand from memory and showed a row
/// of small tinted capsules with the action names beside them, which is not what the panel looks
/// like at all — it is a name *above* a large soft button, in equal-width columns, on the app's
/// elevated bar background. The maintainer spotted it immediately.
///
/// Buttons are not used here — a figure must not be clickable — so the labels are drawn directly.
private struct BulkActionsFigure: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bulk Actions", systemImage: "checklist")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("3 items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
                Spacer(minLength: 12)
                Label("Cancel Selection", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 130, alignment: .leading)

            Divider()

            ActionBarColumn(title: "Move to Category") {
                SoftIconLabel(systemImage: "folder", tint: .indigo)
            }
            ActionBarColumn(title: "Match Self Service Category") {
                SoftIconLabel(systemImage: "arrow.triangle.2.circlepath", tint: .teal)
            }
            ActionBarColumn(title: "Edit Policies (3)") {
                SoftIconLabel(systemImage: "slider.horizontal.3", tint: .indigo)
            }
            ActionBarColumn(title: "Clone Selected (3)") {
                SoftIconLabel(systemImage: "doc.on.doc", tint: .purple)
            }
            ActionBarColumn(title: "Delete Selection") {
                SoftIconLabel(systemImage: "trash.fill", tint: .red)
            }
        }
        .padding(16)
        .frame(width: 620)
        .appBarBackground(cornerRadius: 16)
    }
}

/// The two badges a row can carry — the **real** `StatusBadge`, not a copy of it.
///
/// Both cases are drawn side by side because the point is that they differ by **symbol** as well as
/// colour: nothing in this app tells you something by colour alone.
private struct StatusBadgesFigure: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([JamfItemStatus.active, .inactive]) { status in
                StatusBadge(status: status)
            }
        }
    }
}







/// The single-item action bar: the same columns, named for one object rather than a selection.
private struct SingleActionBarFigure: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Policy", systemImage: AppModule.policies.icon)
                    .font(.headline)
                Text("Cursorai")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("ID: 144")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
                Spacer(minLength: 12)
                Label("Cancel Selection", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 130, alignment: .leading)

            Divider()

            ActionBarColumn(title: "Move to Category") {
                SoftIconLabel(systemImage: "folder", tint: .indigo)
            }
            ActionBarColumn(title: "Match Self Service Category") {
                SoftIconLabel(systemImage: "arrow.triangle.2.circlepath", tint: .teal)
            }
            ActionBarColumn(title: "Edit Policy") {
                SoftIconLabel(systemImage: "slider.horizontal.3", tint: .indigo)
            }
            ActionBarColumn(title: "Clone Policy") {
                SoftIconLabel(systemImage: "doc.on.doc", tint: .purple)
            }
            ActionBarColumn(title: "Delete Policy") {
                SoftIconLabel(systemImage: "trash.fill", tint: .red)
            }
        }
        .padding(16)
        .frame(width: 620)
        .appBarBackground(cornerRadius: 16)
    }
}

// MARK: - Workflow figures
//
// These are the figures that explain a *job* rather than name a control: the deployment sheet, the
// upload, version pinning. Each carries `FigureMarker`s, and the prose beside it points at them by
// number, so a paragraph can name one field out of a dozen without describing where it sits.







/// The Unused audit's action bar — the same shared components, with its own three actions.
///
/// Its columns are ordered by how easily each can be undone, which is the module's whole argument:
/// **Move to Category** first because it changes nothing but where a thing is filed, **Disable**
/// next because Policies can put it back, **Delete** last because nothing can.
private struct UnusedActionsFigure: View {
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bulk Actions", systemImage: "checklist")
                    .font(.headline)
                Text("3 items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
                Spacer(minLength: 12)
                Label("Cancel Selection", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 130, alignment: .leading)

            Divider()

            ActionBarColumn(title: "Move to Category") {
                SoftIconLabel(systemImage: "folder", tint: .indigo)
            }
            ActionBarColumn(title: "Disable (2)") {
                SoftIconLabel(systemImage: "pause.circle", tint: .orange)
            }
            ActionBarColumn(title: "Delete Selection") {
                SoftIconLabel(systemImage: "trash.fill", tint: .red)
            }
        }
        .padding(16)
        .frame(width: 560)
        .appBarBackground(cornerRadius: 16)
    }
}



// MARK: - Figures built from the module's own views
//
// Every figure below instantiates the **real** view the module uses, with sample data. Nothing here
// re-draws a row: `PolicyCardView`, `ProfileCardView`, `PackageCardView`, `BlueprintCardView`,
// `RedundantRowView` and `StatCard` all take a model and no service, which is what makes this
// possible — and what makes these figures unable to drift. The first pass at this guide drew several
// of them by hand and they were wrong in ways nobody would notice until a reader did.

/// Dashboard tiles — the real `StatCard`, in the three states a tile can be in.
private struct DashboardTilesFigure: View {
    var body: some View {
        HStack(spacing: 12) {
            StatCard(title: "Policies", count: 249,
                     icon: AppModule.policies.icon, color: .moduleMagenta)
            StatCard(title: "Unused", count: 14,
                     icon: AppModule.redundant.icon, color: .moduleRose,
                     detail: "Items to review", isLoading: true)
            StatCard(title: "Blueprints", count: nil,
                     icon: AppModule.blueprints.icon, color: .moduleCyan)
        }
        .frame(width: 560)
    }
}

/// A policy row — `PolicyCardView`, exactly as the list draws it.
private struct PolicyRowFigure: View {
    var body: some View {
        VStack(spacing: 8) {
            PolicyCardView(policy: Policy(id: 143, name: "Claude Desktop",
                                          categoryId: 1, categoryName: "AI Tools",
                                          enabled: true, scope: nil,
                                          scopeTargetsAnything: true),
                           categoryName: "AI Tools")
            PolicyCardView(policy: Policy(id: 205, name: "Install Github Copilot",
                                          categoryId: 1, categoryName: "AI Tools",
                                          enabled: false, scope: nil,
                                          scopeTargetsAnything: false),
                           categoryName: "AI Tools")
        }
        .frame(width: 560)
    }
}

/// Two profile rows — `ProfileCardView` — one scoped, one not.
private struct ProfileRowFigure: View {
    var body: some View {
        VStack(spacing: 8) {
            ProfileCardView(profile: ConfigProfile(id: 61, name: "FileVault Escrow",
                                                   categoryName: "Management",
                                                   isActive: true),
                            categoryName: "Management")
            ProfileCardView(profile: ConfigProfile(id: 74, name: "Legacy Wi-Fi",
                                                   categoryName: "Network Settings",
                                                   isActive: false),
                            categoryName: "Network Settings")
        }
        .frame(width: 560)
    }
}

/// Blueprint rows — `BlueprintCardView`, with the state the server reports.
///
/// `Blueprint` has a custom `init(from:)` rather than a memberwise one, so the samples are **decoded
/// from JSON** here. That is a feature, not a workaround: the figure's data goes through exactly the
/// decoding path a real blueprint does, so a change to the coding keys breaks the figure too.
///
/// The card's actions are closures; a figure is not interactive, so they are empty and the whole
/// card is behind `allowsHitTesting(false)` in `HelpFigureCard`.
private struct BlueprintRowFigure: View {
    private static func sample(_ json: String) -> Blueprint? {
        try? JSONDecoder().decode(Blueprint.self, from: Data(json.utf8))
    }

    private static let samples: [Blueprint] = [
        sample(#"{"id":"b1","name":"Passcode policy","description":"Minimum length and grace period","deploymentState":"DEPLOYED"}"#),
        sample(#"{"id":"b2","name":"Extensible SSO","description":"Platform SSO for the identity provider"}"#),
    ].compactMap { $0 }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Self.samples) { blueprint in
                BlueprintCardView(blueprint: blueprint,
                                  onInspect: {}, onEdit: {},
                                  onDeploy: {}, onUndeploy: {}, onDelete: {})
            }
        }
        .frame(width: 560)
    }
}

/// A package row from Jamf's library — the same `PackageCardView` the library list uses.
private struct PackageRowFigure: View {
    var body: some View {
        PackageCardView(item: InstallomatorItem(
            label: "1password8", displayName: "1Password 8",
            isDeployed: true, policyID: 88, policyName: "Install 1Password 8",
            categoryName: "Security", enabled: true, pinnedVersion: nil,
            existingPolicyName: nil, labelExistsUpstream: true), isSelected: false)
        .frame(width: 560)
    }
}

/// The four Installomator views, and what a row looks like in three of the states.
///
/// The view picker iterates `PackageViewMode.allCases`; the rows are `PackageCardView`, so the
/// status colour and symbol on each come from `InstallomatorItem` itself rather than from a guess.
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
                        .background(AppModule.installomator.accentColour
                                        .opacity(mode == selected ? 0.20 : 0.06),
                                    in: .capsule)
                }
            }

            PackageCardView(item: InstallomatorItem(
                label: "googlechrome", displayName: "Google Chrome",
                isDeployed: true, policyID: 12, policyName: "Install Google Chrome",
                categoryName: "Web", enabled: true, pinnedVersion: nil,
                existingPolicyName: nil, labelExistsUpstream: true), isSelected: false)

            PackageCardView(item: InstallomatorItem(
                label: "adobeacrobatreader", displayName: "Adobe Acrobat Reader",
                isDeployed: true, policyID: 44, policyName: "Install Adobe Acrobat Reader",
                categoryName: "Creative Apps", enabled: true, pinnedVersion: nil,
                existingPolicyName: nil, labelExistsUpstream: false), isSelected: false)

            PackageCardView(item: InstallomatorItem(
                label: "slack", displayName: "Slack",
                isDeployed: false, policyID: nil, policyName: nil,
                categoryName: nil, enabled: false, pinnedVersion: nil,
                existingPolicyName: nil, labelExistsUpstream: true), isSelected: false)
        }
        .frame(width: 560, alignment: .leading)
    }
}

/// Unused audit rows — `RedundantRowView`, one per reason, each carrying its own `ReasonBadge`.
private struct UnusedRowsFigure: View {
    var body: some View {
        VStack(spacing: 8) {
            RedundantRowView(item: RedundantItem(
                kind: .policy, jamfID: "31", name: "Old onboarding script",
                categoryName: "Onboarding", reasons: [.notEnabled],
                isEnabled: false, isInstallomator: false))
            RedundantRowView(item: RedundantItem(
                kind: .profile, jamfID: "74", name: "Legacy Wi-Fi",
                categoryName: "Network Settings", reasons: [.notScoped],
                isEnabled: nil, isInstallomator: false))
            RedundantRowView(item: RedundantItem(
                kind: .package, jamfID: "102", name: "SomeTool-2.4.pkg",
                categoryName: "Utilities and tools", reasons: [.notAttached],
                isEnabled: nil, isInstallomator: false), isSelectable: false)
        }
        .frame(width: 560)
    }
}
