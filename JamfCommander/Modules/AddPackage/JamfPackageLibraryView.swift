//
//  JamfPackageLibraryView.swift
//  JamfCommander
//
//  The packages already in Jamf, listed the way the Installomator manager lists labels: a search
//  field, A–Z or category grouping, collapsible sections, and one card per package.
//
//  Whether a package is *deployed* is the one thing this view cannot know cheaply — Jamf has no
//  reverse lookup from package to policy, so the answer arrives from a background scan
//  (`scanPackageEstate`). Until it does, rows say "Checking…" rather than implying a package is
//  unused, which would be the more damaging thing to get wrong.
//

import SwiftUI

struct JamfPackageLibraryView: View {
    let packages: [JamfPackage]
    /// Package id → the policies that install it. Empty until the scan finishes.
    let usage: [String: [String]]
    /// Jamf category id → name, for grouping and for the row's folder badge.
    let categoryNames: [String: String]
    let isScanning: Bool
    let scanFailed: Bool

    @Binding var groupMode: PackageGroupMode
    @Binding var searchText: String

    let emptyTitle: String
    let emptyDetail: String

    var body: some View {
        // The search field and the scan banner are attached as a top safe-area inset rather than
        // stacked above the list in a VStack.
        //
        // As VStack siblings they counted towards this view's minimum height. When the banner
        // appeared mid-scan the module's content exceeded the window, and the overflow was split
        // evenly top and bottom: the "Package Manager" header and search field vanished off the
        // top, and the sidebar was sliced under the traffic lights. An inset is laid out around
        // the content instead of adding to it, so it cannot push the module past the window.
        Group {
            if filteredPackages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedPackages, id: \.key) { group in
                            CollapsibleJamfPackageSection(
                                sectionTitle: group.key,
                                groupMode: groupMode,
                                packages: group.value,
                                usage: usage,
                                categoryNames: categoryNames,
                                isScanning: isScanning
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                searchBar

                if scanFailed {
                    banner(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: "Could not work out which packages are attached to a policy. The list below is complete, but the deployed state is unknown."
                    )
                } else if isScanning {
                    banner(
                        icon: "clock.arrow.circlepath",
                        tint: .secondary,
                        text: "Checking which packages are attached to a policy. Every policy has to be read for this, so it takes a moment."
                    )
                }
            }
        }
    }

    // MARK: - Filtering and grouping

    private var filteredPackages: [JamfPackage] {
        guard !searchText.isEmpty else { return packages }
        return packages.filter { package in
            package.displayName.localizedCaseInsensitiveContains(searchText)
                || package.fileName.localizedCaseInsensitiveContains(searchText)
                || (categoryName(for: package)?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var groupedPackages: [(key: String, value: [JamfPackage])] {
        switch groupMode {
        case .alphabetical:
            let grouped = Dictionary(grouping: filteredPackages) { package -> String in
                let first = package.displayName.prefix(1).uppercased()
                return first.rangeOfCharacter(from: .letters) != nil ? first : "#"
            }
            return grouped.sorted { $0.key < $1.key }
        case .category:
            let grouped = Dictionary(grouping: filteredPackages) { categoryName(for: $0) ?? "Uncategorised" }
            return grouped.sorted { $0.key < $1.key }
        }
    }

    private func categoryName(for package: JamfPackage) -> String? {
        guard let categoryID = package.categoryID else { return nil }
        return categoryNames[categoryID]
    }

    // MARK: - Chrome

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search packages, file names or categories...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            Text("\(filteredPackages.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(text)
                .font(.caption)
                // Bounded deliberately. With fixedSize alone this wraps to whatever width it is
                // offered, and when that measurement happens before the width is known it grows to
                // dozens of lines — which is what pushed the whole split view past the window
                // height and clipped the header and sidebar during a scan.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "shippingbox" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? emptyTitle : "No matches")
                .font(.title3)
                .fontWeight(.medium)
            Text(searchText.isEmpty ? emptyDetail : "No package matches “\(searchText)”.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                // Width-bounded and line-bounded on purpose. fixedSize alone wraps to whatever
                // width it is offered, and this view sits outside a ScrollView, so when it was
                // measured before its width resolved it reported a huge height and pushed the
                // whole split view past the window. A centred paragraph should not span the full
                // window in any case.
                .frame(maxWidth: 420)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !searchText.isEmpty {
                Button("Clear Search") { searchText = "" }
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section

/// One collapsible group of packages. Deliberately the same shape as the Installomator manager's
/// sections so the two lists read as one app rather than two.
private struct CollapsibleJamfPackageSection: View {
    let sectionTitle: String
    let groupMode: PackageGroupMode
    let packages: [JamfPackage]
    let usage: [String: [String]]
    let categoryNames: [String: String]
    let isScanning: Bool

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    if groupMode == .category {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.blue)
                        Text(sectionTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                    } else {
                        Text(sectionTitle)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .frame(width: 28)
                    }

                    Text("\(packages.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Spacer()
                }
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(packages) { package in
                        JamfPackageRow(
                            package: package,
                            categoryName: package.categoryID.flatMap { categoryNames[$0] },
                            policyNames: usage[package.id] ?? [],
                            isScanning: isScanning
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Row

/// One package, styled to match `PackageCardView` in the Installomator manager.
private struct JamfPackageRow: View {
    let package: JamfPackage
    let categoryName: String?
    let policyNames: [String]
    let isScanning: Bool

    private var isDeployed: Bool { !policyNames.isEmpty }

    /// While the scan is running, an unattached package is genuinely unknown rather than unused —
    /// saying "Not in a policy" too early is the version of this that misleads.
    private var statusText: String {
        if isDeployed { return "Deployed" }
        return isScanning ? "Checking…" : "Not in a policy"
    }

    private var statusColor: Color {
        if isDeployed { return .green }
        return isScanning ? .secondary : .blue
    }

    private var statusIcon: String {
        if isDeployed { return "checkmark.seal.fill" }
        return isScanning ? "clock" : "shippingbox.fill"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 42, height: 42)

                Image(systemName: statusIcon)
                    .font(.system(size: 20))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(package.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                        Text(package.fileName.isEmpty ? "No file name" : package.fileName)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .foregroundColor(statusColor)
                    .cornerRadius(4)

                    Text("ID: \(package.id)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)

                    Text("•")
                        .foregroundColor(.secondary)

                    Label(categoryName ?? "Uncategorised", systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if isDeployed {
                    Label(policySummary, systemImage: "scroll")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(policyNames.joined(separator: "\n"))
                }
            }

            Spacer()

            Text(statusText)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15))
                .foregroundColor(statusColor)
                .cornerRadius(6)
        }
        .padding(12)
        .liquidGlass(cornerRadius: 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(package.displayName). \(statusText). \(isDeployed ? policySummary : "")")
    }

    /// "Installed by Acme Reader" for one, "Installed by 3 policies" beyond that — the full list is in
    /// the tooltip rather than wrapped across the row.
    private var policySummary: String {
        if policyNames.count == 1 {
            return "Installed by \(policyNames[0])"
        }
        return "Installed by \(policyNames.count) policies"
    }
}
