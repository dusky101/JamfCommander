//
//  RedundantDashboardView.swift
//  JamfCommander
//
//  The Redundant audit: everything in Jamf that looks like it does nothing.
//
//  Read-only. It finds and explains; it does not change anything. The rules it applies — and what
//  they cannot see — are written down in `RedundantModels.swift`, and every row shows the reason it
//  was listed rather than a blanket "unused".
//
//  The scan is the expensive one. `scanPolicyEstate` reads every policy once and answers three
//  questions from the same record (the policy itself, the packages it installs, whether it is an
//  Installomator deployment), so this page costs one pass over the policies rather than three.
//  Profiles and the package library are separate reads on top of that. It runs on open and on
//  Refresh, never on a keystroke.
//
//  All four reads must succeed. A partial audit is worse than none: an empty section would read as
//  "nothing of this kind is redundant" when it actually means "this could not be checked", and that
//  is exactly the misreading that gets something deleted.
//

import SwiftUI

struct RedundantDashboardView: View {
    @ObservedObject var api: JamfAPIService

    @State private var items: [RedundantItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var hasLoaded = false

    @State private var filter: RedundantFilter = .all
    @State private var searchText = ""
    @State private var collapsedKinds: Set<RedundantKind> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Scan Jamf again")
                .disabled(isLoading)
            }
        }
        .task {
            // The scan is far too heavy to repeat every time the module is shown.
            guard !hasLoaded else { return }
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redundant")
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            if !isLoading && !loadFailed && !items.isEmpty {
                filterChips
                searchField

                // Said plainly, because the audit's weakest claim is the one most likely to be
                // acted on. See the header of RedundantModels.swift.
                Label(
                    "\"Not scoped\" means no computers or computer groups are targeted. Scoping by building, department or user is not read, so check anything unexpected in Jamf before acting on it.",
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var subtitle: String {
        if isLoading { return "Reading every policy, profile and package in this instance." }
        if loadFailed { return "The audit could not be completed." }
        if items.isEmpty { return "Nothing in this instance looks redundant." }
        return "\(items.count) object\(items.count == 1 ? "" : "s") that look like they do nothing."
    }

    private var filterChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(RedundantFilter.allCases) { option in
                FilterChip(
                    title: option.rawValue,
                    icon: option.icon,
                    color: .blue,
                    isSelected: filter == option,
                    count: count(for: option)
                ) {
                    withAnimation { filter = option }
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search names, categories or IDs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingProgressView(
                message: "Scanning Jamf for redundant objects...",
                detail: "Reading every policy, profile and package. This takes a while on a large instance."
            )
        } else if loadFailed {
            errorView
        } else if items.isEmpty {
            emptyView(
                title: "Nothing looks redundant",
                detail: "Every policy is enabled and scoped, every profile is scoped, and every package is installed by a policy."
            )
        } else if groupedItems.isEmpty {
            emptyView(
                title: "Nothing matches this filter",
                detail: "Clear the search, or choose All to see everything the scan found."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groupedItems, id: \.kind) { group in
                        section(for: group.kind, items: group.items)
                    }
                }
                .padding()
            }
        }
    }

    private func section(for kind: RedundantKind, items: [RedundantItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsedKinds.contains(kind) {
                        collapsedKinds.remove(kind)
                    } else {
                        collapsedKinds.insert(kind)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .rotationEffect(.degrees(collapsedKinds.contains(kind) ? 0 : 90))

                    Label(kind.rawValue, systemImage: kind.icon)
                        .font(.headline)

                    Text("\(items.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    if !kind.supportsActions {
                        Text("Report only")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                            .help("Packages are listed so you can see them. Removing a package record is done in Jamf.")
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .accessibilityLabel("\(kind.rawValue), \(items.count) item\(items.count == 1 ? "" : "s")")
            .accessibilityHint(collapsedKinds.contains(kind) ? "Expand this section" : "Collapse this section")

            if !collapsedKinds.contains(kind) {
                ForEach(items) { item in
                    RedundantRowView(item: item)
                }
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Couldn't complete the audit")
                .font(.headline)

            Text("The audit needs every policy, profile and package to be read before it can call anything redundant, and one of those reads failed. Check your connection to Jamf, and that this API client can read policies, configuration profiles, packages and categories, then try again. Nothing has been changed.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try Again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
    }

    private func emptyView(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundColor(.green)

            Text(title)
                .font(.headline)

            Text(detail)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived

    private var filteredItems: [RedundantItem] {
        let byReason = items.filter { filter.matches($0) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return byReason }

        return byReason.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.categoryName.localizedCaseInsensitiveContains(query)
                || $0.jamfID == query
        }
    }

    private var groupedItems: [(kind: RedundantKind, items: [RedundantItem])] {
        RedundantKind.allCases.compactMap { kind in
            let matching = filteredItems.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind: kind, items: matching)
        }
    }

    private func count(for option: RedundantFilter) -> Int {
        items.filter { option.matches($0) }.count
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        loadFailed = false

        // Widens Installomator detection past "the policy's script is called Installomator". A
        // failure here only narrows detection, so it degrades rather than failing the scan.
        let knownScriptIDs = (try? await api.fetchInstallomatorScriptIDs()) ?? []

        async let estateResult = api.scanPolicyEstate(knownScriptIDs: knownScriptIDs)
        async let profilesResult = api.fetchProfiles()
        async let packagesResult = api.fetchJamfPackages()
        async let categoriesResult = api.fetchCategories()

        do {
            let estate = try await estateResult
            let profiles = try await profilesResult
            let packages = try await packagesResult
            let categories = try await categoriesResult

            let categoryNames = Dictionary(
                categories.map { (String($0.id), $0.name) },
                uniquingKeysWith: { first, _ in first }
            )

            let audit = RedundantAudit.items(
                policies: estate.policies,
                profiles: profiles,
                packages: packages,
                packageUsage: estate.packageUsage,
                installomatorPolicyIDs: Set(estate.installomator.map(\.policyID)),
                categoryNames: categoryNames
            )

            await MainActor.run {
                items = audit
                isLoading = false
                hasLoaded = true
            }
        } catch {
            // Deliberately no error body in the log — see root CLAUDE.md, invariant 4.
            print("[Redundant] Audit scan failed")
            await MainActor.run {
                items = []
                isLoading = false
                loadFailed = true
            }
        }
    }
}
