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

    @State private var categories: [Category] = []

    @State private var filter: RedundantFilter = .all
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @State private var collapsedKinds: Set<RedundantKind> = []

    // Selection & actions
    @State private var selection: Set<String> = []
    @State private var isWorking = false
    @State private var results: [OperationResult] = []
    @State private var resultTitle = ""
    @State private var showResults = false

    var body: some View {
        VStack(spacing: 0) {
            // --- Top Bar --- the same swap the Policies module makes: filters until something is
            // selected, then the actions for what is selected.
            if !selection.isEmpty {
                RedundantActionPanel(
                    categories: categories,
                    selectedItems: selectedItems,
                    isBusy: isWorking,
                    onClearSelection: { withAnimation { selection.removeAll() } },
                    onConfirmedAction: { action, targets in perform(action, on: targets) }
                )
                .frame(height: 180)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            } else {
                VStack(spacing: 0) {
                    FilterBar(
                        searchText: $searchText,
                        categories: categories,
                        selectedCategory: $selectedCategory,
                        customCount: { category in
                            items.filter { $0.categoryName == category.name }.count
                        },
                        customTotal: items.count,
                        onRefresh: { Task { await load() } },
                        onExport: { exportAudit() }
                    )

                    reasonBar
                }
                .zIndex(1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            content
        }
        // Pin to the top. Without this, content taller than the pane is centred, so the overflow is
        // split above and below and the bar disappears under the title bar instead of the list
        // simply running off the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: selection.isEmpty)
        .task {
            // The scan is far too heavy to repeat every time the module is shown.
            guard !hasLoaded else { return }
            await load()
        }
        .sheet(isPresented: $showResults) {
            OperationResultView(title: resultTitle, results: results) {
                showResults = false
            }
        }
    }

    // MARK: - Reason filters + select all

    /// The audit's own filters, under the shared category bar: which *reason* to show, and a select
    /// all for everything currently listed.
    private var reasonBar: some View {
        HStack(spacing: 8) {
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
                .help(option.reason?.explanation ?? "Everything the scan found")
            }

            Spacer()

            if !filteredItems.isEmpty {
                Text("\(filteredItems.count) shown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(allActionableSelected ? "Clear Selection" : "Select All (\(actionableFilteredItems.count))") {
                withAnimation { toggleSelectAll() }
            }
            .disabled(actionableFilteredItems.isEmpty)
            .help("Select every policy and profile currently listed. Packages are report only.")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
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
                    if item.kind.supportsActions {
                        Button {
                            toggle(item)
                        } label: {
                            RedundantRowView(item: item, isSelected: selection.contains(item.id))
                        }
                        .buttonStyle(.plain)
                    } else {
                        RedundantRowView(item: item, isSelectable: false)
                    }
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return items.filter { item in
            guard filter.matches(item) else { return false }
            if let selectedCategory, item.categoryName != selectedCategory.name { return false }
            guard !query.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(query)
                || item.categoryName.localizedCaseInsensitiveContains(query)
                || item.jamfID == query
        }
    }

    /// Only what the audit can actually change. Packages are listed but never acted on, so they are
    /// never selected either — a selection that silently does nothing is worse than no selection.
    private var actionableFilteredItems: [RedundantItem] {
        filteredItems.filter { $0.kind.supportsActions }
    }

    private var selectedItems: [RedundantItem] {
        items.filter { selection.contains($0.id) }
    }

    private var allActionableSelected: Bool {
        !actionableFilteredItems.isEmpty
            && actionableFilteredItems.allSatisfy { selection.contains($0.id) }
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

    // MARK: - Selection

    private func toggle(_ item: RedundantItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private func toggleSelectAll() {
        let visible = Set(actionableFilteredItems.map(\.id))
        if allActionableSelected {
            selection.subtract(visible)
        } else {
            selection.formUnion(visible)
        }
    }

    // MARK: - Acting

    /// Runs a confirmed action and reports exactly what Jamf did with each item.
    ///
    /// The list is then brought in line with what actually succeeded rather than re-scanned: a full
    /// scan reads every policy, profile and package again, which is far too much to pay after every
    /// action. Refresh re-reads Jamf when certainty is wanted.
    private func perform(_ action: JamfAPIService.RedundantAction, on targets: [RedundantItem]) {
        guard !targets.isEmpty, !isWorking else { return }
        isWorking = true

        Task {
            let outcome = await api.applyRedundantAction(action, to: targets)
            let changed = Set(outcome.filter(\.success).compactMap(\.itemID))

            await MainActor.run {
                applyLocally(action, to: changed)
                selection.subtract(changed)
                results = outcome
                resultTitle = action.title
                isWorking = false
                showResults = true
            }
        }
    }

    /// Reflects a completed action in the list.
    ///
    /// Only a delete removes a row. A move changes where something is filed but not whether it is
    /// redundant, and disabling an unscoped policy makes it *more* redundant, not less — so both
    /// keep their row, updated.
    private func applyLocally(_ action: JamfAPIService.RedundantAction, to changed: Set<String>) {
        guard !changed.isEmpty else { return }

        switch action {
        case .delete:
            items.removeAll { changed.contains($0.id) }

        case .disable:
            items = items.map { item in
                guard changed.contains(item.id) else { return item }
                return RedundantItem(
                    kind: item.kind,
                    jamfID: item.jamfID,
                    name: item.name,
                    categoryName: item.categoryName,
                    reasons: item.reasons.union([.notEnabled]),
                    isEnabled: false,
                    isInstallomator: item.isInstallomator
                )
            }

        case .moveToCategory(_, let name):
            items = items.map { item in
                guard changed.contains(item.id) else { return item }
                return RedundantItem(
                    kind: item.kind,
                    jamfID: item.jamfID,
                    name: item.name,
                    categoryName: name,
                    reasons: item.reasons,
                    isEnabled: item.isEnabled,
                    isInstallomator: item.isInstallomator
                )
            }
        }
    }

    // MARK: - Report

    /// Writes what is currently listed to CSV — the audit as a record you can take away, circulate,
    /// or work through outside the app. Exports the filtered view, not the whole scan, so what you
    /// are looking at is what you get.
    private func exportAudit() {
        let csv = RedundantExportService.exportToCSV(items: filteredItems)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        _ = ExportService.saveCSVToFile(
            content: csv,
            defaultName: "Redundant_\(formatter.string(from: Date())).csv"
        )
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
                self.categories = categories.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                // A row that has gone is no longer selectable; drop it rather than acting on a
                // selection that no longer matches what is on screen.
                selection = selection.intersection(Set(audit.map(\.id)))
                isLoading = false
                hasLoaded = true
            }
        } catch {
            // Deliberately no error body in the log — see root CLAUDE.md, invariant 4.
            print("[Redundant] Audit scan failed")
            await MainActor.run {
                items = []
                selection.removeAll()
                isLoading = false
                loadFailed = true
            }
        }
    }
}
