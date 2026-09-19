//
//  ScriptsDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct ScriptsDashboardView: View {
    @ObservedObject var api: JamfAPIService
    @ObservedObject private var refreshCoordinator = RefreshCoordinator.shared

    @State private var scripts: [ScriptRecord] = []
    @State private var categories: [Category] = []
    @State private var searchText = ""
    @State private var selectedCategory: Category?
    @State private var isLoading = true
    @State private var inspectorSelection: InspectorSelection?

    // Selection
    @State private var selectedScriptIDs = Set<String>()
    @State private var isBusy = false
    @State private var confirmation: ConfirmationData?
    @State private var results: [OperationResult] = []
    @State private var resultTitle = "Scripts"
    @State private var showResults = false

    var filteredScripts: [ScriptRecord] {
        scripts.filter { script in
            let matchesText = searchText.isEmpty
                || script.name.localizedCaseInsensitiveContains(searchText)
                || script.id == searchText
            let matchesCategory = selectedCategory == nil || script.safeCategory == selectedCategory?.name
            return matchesText && matchesCategory
        }
    }

    var groupedScripts: [(key: String, value: [ScriptRecord])] {
        let grouped = Dictionary(grouping: filteredScripts) { $0.safeCategory }
        return grouped.sorted { $0.key < $1.key }
    }

    private var selectedScripts: [ScriptRecord] {
        scripts.filter { selectedScriptIDs.contains($0.id) }
    }

    /// Jamf has no category for "no category", so scripts without one would group under a heading the
    /// filter bar could not offer a chip for. This adds that chip, with a sentinel id no real Jamf
    /// category can hold.
    private static let uncategorisedName = "Uncategorised"

    private var filterCategories: [Category] {
        var list = categories
        if scripts.contains(where: { $0.safeCategory == Self.uncategorisedName }) {
            list.append(Category(id: -1, name: Self.uncategorisedName))
        }
        return list
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Top Bar --- the swap every other module makes: filters until something is
            // selected, then what you can do to it.
            if !selectedScriptIDs.isEmpty {
                ScriptActionBar(
                    selectedScripts: selectedScripts,
                    isBusy: isBusy,
                    categories: categories,
                    onClearSelection: { withAnimation { selectedScriptIDs.removeAll() } },
                    onRequestMove: { targets, category in requestMove(targets, to: category) },
                    onRequestDelete: { targets in requestDelete(targets) }
                )
                .frame(height: 180)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            } else {
                FilterBar(
                    searchText: $searchText,
                    categories: filterCategories,
                    selectedCategory: $selectedCategory,
                    customCount: { category in
                        scripts.filter { $0.safeCategory == category.name }.count
                    },
                    customTotal: scripts.count,
                    onRefresh: { Task { await refreshData() } },
                    onExport: { exportScripts() }
                )
                .zIndex(1)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // --- Content ---
            if isLoading {
                ProgressView("Loading Scripts...")
                    .frame(maxHeight: .infinity)
            } else if groupedScripts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedScripts, id: \.key) { group in
                            ScriptCategorySection(
                                title: group.key,
                                scripts: group.value,
                                categories: categories,
                                selectedIDs: $selectedScriptIDs,
                                onInspect: { id in
                                    inspectorSelection = InspectorSelection(id: id)
                                },
                                onMove: { script, category in requestMove([script], to: category) },
                                onDelete: { script in requestDelete([script]) }
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 50)
                }
            }
        }
        // Pin to the top, as the other modules do: content taller than the pane would otherwise be
        // centred and its overflow split above and below.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: selectedScriptIDs.isEmpty)
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showResults) {
            OperationResultView(title: resultTitle, results: results) {
                showResults = false
                Task { await refreshData() }
            }
        }
        .task {
            await refreshData()
        }
        .onChange(of: refreshCoordinator.token) { Task { await refreshData() } }
        .sheet(item: $inspectorSelection) { selection in
            ScriptInspectorView(scriptId: selection.id, api: api)
        }
    }
    
    // MARK: - Actions
    
    private func refreshData() async {
        do {
            async let scriptsResult = api.fetchScripts()
            // Advisory: the filter bar's chips need these, but a failure to read them only costs the
            // category filter, so it must not fail the whole load.
            let fetchedCategories = try? await api.fetchCategories()

            self.scripts = try await scriptsResult
            self.categories = (fetchedCategories ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // A script that has gone is no longer selectable.
            self.selectedScriptIDs = selectedScriptIDs.intersection(Set(scripts.map(\.id)))
            self.isLoading = false
        } catch {
            // No error body in the log — see root CLAUDE.md, invariant 4.
            print("[Scripts] Script load failed")
            self.isLoading = false
        }
    }

    /// Nothing to show, and which kind of nothing it is.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: scripts.isEmpty ? "applescript" : "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)

                Text(scripts.isEmpty ? "No scripts in this instance" : "No matches")
                    .font(.headline)

                Text(emptyDetail)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !searchText.isEmpty || selectedCategory != nil {
                    Button("Clear Filters") {
                        searchText = ""
                        selectedCategory = nil
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetail: String {
        if scripts.isEmpty {
            return "This Jamf instance has no scripts, or none this API client may read."
        }
        if !searchText.isEmpty, let selectedCategory {
            return "No script in \(selectedCategory.name) matches “\(searchText)”."
        }
        if !searchText.isEmpty {
            return "No script matches “\(searchText)”."
        }
        if let selectedCategory {
            return "No script is filed under \(selectedCategory.name)."
        }
        return "Nothing matches the current filters."
    }

    /// Asks before moving. Reversible by hand, so the wording says so rather than warning.
    private func requestMove(_ targets: [ScriptRecord], to category: Category) {
        guard !targets.isEmpty else { return }

        let what = targets.count == 1 ? "“\(targets[0].name)”" : "\(targets.count) scripts"
        confirmation = ConfirmationData(
            title: "Move \(targets.count == 1 ? "this script" : "\(targets.count) scripts") to \(category.name)?",
            message: "\(what) will be filed under \(category.name). The script itself is unchanged, and any policy that runs it carries on running it.",
            actionTitle: targets.count == 1 ? "Move" : "Move \(targets.count)",
            role: nil,
            action: { performMove(targets, to: category) }
        )
    }

    /// Moves the confirmed scripts, reporting the real outcome of each.
    private func performMove(_ targets: [ScriptRecord], to category: Category) {
        guard !targets.isEmpty, !isBusy else { return }
        isBusy = true

        Task {
            var outcome: [OperationResult] = []
            let batchSize = 5
            let batches = stride(from: 0, to: targets.count, by: batchSize).map {
                Array(targets[$0..<min($0 + batchSize, targets.count)])
            }

            for (index, batch) in batches.enumerated() {
                for script in batch {
                    do {
                        try await api.moveScript(id: script.id, toCategoryID: category.id)
                        outcome.append(
                            OperationResult(
                                itemName: script.name,
                                success: true,
                                error: nil,
                                fromCategory: script.safeCategory,
                                toCategory: category.name
                            )
                        )
                    } catch {
                        outcome.append(
                            OperationResult(
                                itemName: script.name,
                                success: false,
                                error: "Jamf rejected the move. Check this API client may update scripts, then try again — the script itself is unchanged."
                            )
                        )
                    }
                }
                if index < batches.count - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            await MainActor.run {
                results = outcome.sorted { lhs, rhs in
                    if lhs.success != rhs.success { return !lhs.success }
                    return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
                }
                resultTitle = "Move to \(category.name)"
                isBusy = false
                showResults = true
            }
        }
    }

    /// Asks before deleting. Shared by the action bar and the row context menu, so a delete is
    /// confirmed the same way however it was started.
    private func requestDelete(_ targets: [ScriptRecord]) {
        guard !targets.isEmpty else { return }

        let names = targets.count == 1 ? "“\(targets[0].name)”" : "\(targets.count) scripts"
        confirmation = ConfirmationData(
            title: targets.count == 1 ? "Delete this script?" : "Delete \(targets.count) scripts from Jamf?",
            message: "This permanently removes \(names) from this Jamf instance and cannot be undone. Any policy that runs one of them will fail from the next time it tries.",
            actionTitle: targets.count == 1 ? "Delete" : "Delete \(targets.count)",
            role: .destructive,
            action: { performDelete(targets) }
        )
    }

    /// Deletes the confirmed scripts, one batch at a time, reporting the real outcome of each.
    private func performDelete(_ targets: [ScriptRecord]) {
        guard !targets.isEmpty, !isBusy else { return }
        isBusy = true

        Task {
            var outcome: [OperationResult] = []

            // Same pacing as every other bulk write in the app.
            let batchSize = 5
            let batches = stride(from: 0, to: targets.count, by: batchSize).map {
                Array(targets[$0..<min($0 + batchSize, targets.count)])
            }

            for (index, batch) in batches.enumerated() {
                for script in batch {
                    do {
                        try await api.deleteScript(id: script.id)
                        outcome.append(OperationResult(itemName: script.name, success: true, error: nil))
                    } catch {
                        outcome.append(
                            OperationResult(
                                itemName: script.name,
                                success: false,
                                error: "Jamf rejected the delete. Check this API client may delete scripts, and that nothing still uses it."
                            )
                        )
                    }
                }
                if index < batches.count - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            await MainActor.run {
                selectedScriptIDs.subtract(Set(outcome.filter(\.success).compactMap { result in
                    targets.first(where: { $0.name == result.itemName })?.id
                }))
                results = outcome.sorted { lhs, rhs in
                    if lhs.success != rhs.success { return !lhs.success }
                    return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
                }
                resultTitle = "Delete Scripts"
                isBusy = false
                showResults = true
            }
        }
    }
    
    private func exportScripts() {
        let csvContent = ExportService.exportScriptsToCSV(scripts: scripts)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        ExportService.saveCSVToFile(content: csvContent, defaultName: "Scripts_\(dateString).csv")
    }
}

// Local Section Component
struct ScriptCategorySection: View {
    let title: String
    let scripts: [ScriptRecord]
    let categories: [Category]
    @Binding var selectedIDs: Set<String>
    var onInspect: (Int) -> Void
    var onMove: (ScriptRecord, Category) -> Void
    var onDelete: (ScriptRecord) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text(title).font(.headline)
                    Spacer()
                    Text("\(scripts.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(10)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // List
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(scripts) { script in
                        ScriptCardView(
                            script: script,
                            categoryName: title,
                            osRequirements: script.osRequirements ?? "Any"
                        )
                        // Tap selects, exactly as it does in Profiles and Policies. It used to open
                        // the inspector, which is why Scripts was the one module where you could not
                        // pick several rows and act on them together.
                        .onTapGesture {
                            toggle(script)
                        }
                        .contextMenu {
                            // Inspecting one row makes no sense while several are selected.
                            if selectedIDs.count <= 1 || !selectedIDs.contains(script.id) {
                                Button("Inspect") { onInspect(script.intId) }
                            }

                            Menu("Move to...") {
                                ForEach(categories) { category in
                                    Button(category.name) { onMove(script, category) }
                                }
                            }

                            Divider()

                            Button("Delete", role: .destructive) { onDelete(script) }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedIDs.contains(script.id) ? Color.blue : Color.clear, lineWidth: 2)
                        )
                        .accessibilityAddTraits(selectedIDs.contains(script.id) ? [.isSelected] : [])
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
    }

    private func toggle(_ script: ScriptRecord) {
        if selectedIDs.contains(script.id) {
            selectedIDs.remove(script.id)
        } else {
            selectedIDs.insert(script.id)
        }
    }
}

/// The Scripts module's bulk action bar, in place of the filter bar once something is selected.
///
/// One action, because deleting is the only thing this app does to a script — it reads them and
/// removes them, and nothing else. Built from the same pieces as the other bars so the module does
/// not look like it belongs to a different app.
struct ScriptActionBar: View {
    let selectedScripts: [ScriptRecord]
    let isBusy: Bool

    let categories: [Category]

    var onClearSelection: () -> Void
    /// The host confirms and performs, so an action started here and one started from a row's
    /// context menu ask the same question.
    var onRequestMove: ([ScriptRecord], Category) -> Void
    var onRequestDelete: ([ScriptRecord]) -> Void

    @State private var showMovePopover = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bulk Actions", systemImage: "checklist")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("\(selectedScripts.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)

                Spacer()

                Button(action: onClearSelection) {
                    Label("Cancel Selection", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .frame(width: 170, alignment: .leading)

            Divider()

            // The reversible one leads, as it does in the other action bars.
            ActionBarColumn(title: "Move to Category") {
                Button { showMovePopover = true } label: {
                    SoftIconLabel(systemImage: "folder", tint: .indigo)
                }
                .buttonStyle(.plain)
                .disabled(isBusy || categories.isEmpty || selectedScripts.isEmpty)
                .help("File the selected scripts under a category")
                .popover(isPresented: $showMovePopover, arrowEdge: .top) {
                    CategoryMovePicker(categories: categories) { category in
                        showMovePopover = false
                        onRequestMove(selectedScripts, category)
                    }
                }
            }

            Divider()

            ActionBarColumn(title: "Delete Selection") {
                SoftIconButton(
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive,
                    isDisabled: isBusy || selectedScripts.isEmpty,
                    help: "Permanently remove the selected scripts from Jamf"
                ) {
                    onRequestDelete(selectedScripts)
                }
            }

            Spacer()
        }
        .padding(20)
        .appBarBackground(cornerRadius: 16)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
}
