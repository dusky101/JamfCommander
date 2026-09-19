//
//  DashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var api: JamfAPIService
    
    // NEW: Binding to control navigation from the stats
    @Binding var currentModule: AppModule

    /// Called once, when the first load finishes — successfully or not. The app blocks interaction
    /// until then, so this must fire on every path out of that first refresh.
    var onInitialLoadFinished: () -> Void = {}

    @State private var hasReportedInitialLoad = false
    
    // Stats State. Optional, not zero: a section of Jamf that could not be read shows "—" on its
    // tile, which is the truth — a 0 would read as "you have none of these".
    @State private var computerCount: Int?
    @State private var profileCount: Int?
    @State private var scriptCount: Int?
    @State private var policyCount: Int?
    @State private var blueprintCount: Int?
    @State private var packageCount: Int?

    // The two headline tiles that cost more than a list fetch, so they fill in after the rest of
    // the Dashboard is already on screen rather than holding it back. `isLoading…` is separate from
    // the count because "still working" and "could not be read" must not look the same: a dash is a
    // statement that the read failed.
    @State private var installomatorLabelCount: Int?
    @State private var installomatorLabelsUpdated: Date?
    @State private var isLoadingInstallomator = true
    @State private var unusedCount: Int?
    @State private var isLoadingUnused = true
    
    // Data Lists
    @State private var categories: [Category] = []
    @State private var computers: [BasicComputerRecord] = [] // For Device Status
    
    // UI State
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showCategorySheet = false
    @State private var categoryToEdit: Category?
    @State private var categoryNameInput = ""
    @State private var categorySaveError: String?
    @State private var isSaving = false
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirmation = false
    @State private var isExporting = false
    @State private var showExportProgress = false
    @StateObject private var exportProgress = ExportProgress()
    /// Collapsed to begin with. Expanded, the category grid is tall enough on a real tenant to push
    /// the totals and Device Status off the screen, so the Dashboard opened on a list of categories
    /// rather than on the overview it exists to give. Opening it is one click.
    @State private var isCategoryManagerExpanded = false
    @State private var expandedDomains: Set<String> = [] // Track which domain groups are expanded
    
    /// The Installomator tile's second line: what the number counts, and how long ago the upstream
    /// list last changed.
    ///
    /// Given as an age rather than a date, which is what GitHub itself shows against the file and
    /// what the question actually is — "is this list current?" is answered by "4 days ago" and needs
    /// arithmetic from "15 Sep". The exact timestamp is the tile's tooltip, for when it matters.
    ///
    /// Omitted rather than faked when GitHub would not give a date.
    private var installomatorDetail: String? {
        guard !isLoadingInstallomator else { return nil }
        guard let updated = installomatorLabelsUpdated else { return "Available labels" }
        // Two deliberate lines rather than one that wraps raggedly: at tile width this runs to about
        // thirty-seven characters, which no sensible column fits on one line.
        return "Available labels\nUpdated \(updated.formatted(.relative(presentation: .named)))"
    }

    /// The exact moment behind the tile's "updated 4 days ago".
    ///
    /// Never empty: `.help("")` would also blank the spoken hint the card carries, so a tile with no
    /// date says what it is instead of saying nothing.
    private var installomatorTooltip: String {
        guard let updated = installomatorLabelsUpdated else {
            return "The labels the Installomator project currently publishes."
        }
        return "Installomator's label list last changed on "
            + updated.formatted(date: .long, time: .shortened)
    }

    /// Says what the Unused number is a count *of*. "Unused: 14" on its own invites the reading
    /// that fourteen things have been deleted.
    private var unusedDetail: String? {
        guard !isLoadingUnused, unusedCount != nil else { return nil }
        return "Items to review"
    }

    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        Group {
        if isLoading {
            LoadingProgressView(message: "Loading Dashboard...")
        } else {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - 1. Hero Stats Grid (Clickable)
                HStack(alignment: .top, spacing: 32) {
                    // Stats Grid (Leading)
                    // `.frame(maxWidth: .infinity)` rather than a trailing Spacer: with a Spacer the
                    // grid was handed only its ideal width and the spacer swallowed the rest, so the
                    // tiles bunched into three columns against a wide empty gap. Filling the row lets
                    // the adaptive columns use the window.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], alignment: .leading, spacing: 16) {
                        
                        Button(action: { currentModule = .computers }) {
                            StatCard(title: "Computers", count: computerCount, icon: "desktopcomputer", color: .moduleAzure)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { currentModule = .policies }) {
                            StatCard(title: "Policies", count: policyCount, icon: "scroll.fill", color: .moduleMagenta)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { currentModule = .profiles }) {
                            StatCard(title: "Profiles", count: profileCount, icon: "doc.text.fill", color: .moduleAmber)
                        }
                        .buttonStyle(.plain)

                        Button(action: { currentModule = .blueprints }) {
                            StatCard(title: "Blueprints", count: blueprintCount, icon: "square.stack.3d.up.fill", color: .moduleCyan)
                        }
                        .buttonStyle(.plain)

                        Button(action: { currentModule = .packages }) {
                            StatCard(title: "Packages", count: packageCount, icon: "shippingbox.fill", color: .moduleViolet)
                        }
                        .buttonStyle(.plain)

                        Button(action: { currentModule = .scripts }) {
                            StatCard(title: "Scripts", count: scriptCount, icon: "applescript.fill", color: .moduleLime)
                        }
                        .buttonStyle(.plain)

                        Button(action: { currentModule = .installomator }) {
                            StatCard(title: "Installomator",
                                     count: installomatorLabelCount,
                                     icon: "arrow.down.app.fill",
                                     color: .moduleSpring,
                                     detail: installomatorDetail,
                                     isLoading: isLoadingInstallomator)
                        }
                        .buttonStyle(.plain)
                        .help(installomatorTooltip)

                        Button(action: { currentModule = .redundant }) {
                            StatCard(title: "Unused",
                                     count: unusedCount,
                                     icon: "archivebox.fill",
                                     color: .moduleRose,
                                     detail: unusedDetail,
                                     isLoading: isLoadingUnused,
                                     animatesArrival: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The tiles fill the row, so without this they run straight into the export
                    // card and the two read as one group.
                    .padding(.trailing, 8)

                    // Export All Button (Trailing)
                    Button(action: { exportAllData() }) {
                        ExportAllCard(isExporting: isExporting)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .frame(width: 140)
                }
                .padding(.horizontal)
                .padding(.top)
                
                Divider().padding(.horizontal)
                
                // MARK: - 2. Category Manager
                VStack(spacing: 16) {
                    HStack {
                        Button(action: { withAnimation { isCategoryManagerExpanded.toggle() } }) {
                            HStack(spacing: 8) {
                                Image(systemName: isCategoryManagerExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption).fontWeight(.bold)
                                Label("Categories", systemImage: "folder.fill")
                                    .font(.title2).fontWeight(.bold)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if isCategoryManagerExpanded {
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                                TextField("Search...", text: $searchText)
                                    .textFieldStyle(.plain).frame(width: 150)
                            }
                            .padding(6).background(Color.black.opacity(0.1)).cornerRadius(8)
                            
                            Button(action: { openCategorySheet(for: nil) }) {
                                Label("New Category", systemImage: "plus").fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if isCategoryManagerExpanded {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                            ForEach(filteredCategories) { category in
                                CategoryTile(
                                    category: category,
                                    onEdit: { openCategorySheet(for: category) },
                                    onDelete: { confirmDelete(category) }
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // MARK: - 3. Device Status (NEW)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Device Status", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.title2).fontWeight(.bold)
                        Spacer()
                        Text("Recent Check-ins")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    
                    // Device List Box - Grouped by Email Domain
                    if computers.isEmpty {
                        VStack {
                            Text("No computers found.").padding()
                                .foregroundColor(.secondary)
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.1), lineWidth: 1))
                    } else {
                        // Group computers by email domain
                        let groupedComputers = Dictionary(grouping: computers.prefix(20), by: { $0.emailDomain })
                        let sortedDomains = groupedComputers.keys.sorted()
                        
                        VStack(spacing: 12) {
                            ForEach(sortedDomains, id: \.self) { domain in
                                let computersInDomain = groupedComputers[domain] ?? []
                                
                                VStack(alignment: .leading, spacing: 0) {
                                    // Domain Header (Collapsible)
                                    Button(action: {
                                        withAnimation {
                                            if expandedDomains.contains(domain) {
                                                expandedDomains.remove(domain)
                                            } else {
                                                expandedDomains.insert(domain)
                                            }
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "envelope.fill")
                                                .foregroundColor(.blue)
                                            
                                            Text(domain)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Text("\(computersInDomain.count)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.secondary)
                                                .rotationEffect(.degrees(expandedDomains.contains(domain) ? 90 : 0))
                                        }
                                        .padding(12)
                                        .background(Color.blue.opacity(0.05))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    // Computers in this domain
                                    if expandedDomains.contains(domain) {
                                        VStack(spacing: 12) {
                                            ForEach(computersInDomain) { comp in
                                                HStack {
                                                    Image(systemName: "desktopcomputer")
                                                        .foregroundColor(.secondary)
                                                        .font(.title3)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(comp.name)
                                                            .fontWeight(.medium)
                                                            .foregroundColor(.primary)
                                                        
                                                        if let email = comp.email, !email.isEmpty {
                                                            HStack(spacing: 4) {
                                                                Image(systemName: "envelope")
                                                                    .font(.caption2)
                                                                Text(email)
                                                            }
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        } else if let username = comp.username, !username.isEmpty {
                                                            HStack(spacing: 4) {
                                                                Image(systemName: "person.crop.circle")
                                                                    .font(.caption2)
                                                                Text(username)
                                                            }
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                        }
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    // Status Badge
                                                    HStack(spacing: 6) {
                                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                                        Text("Active")
                                                    }
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.green)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.green.opacity(0.1))
                                                    .cornerRadius(12)
                                                }
                                                .padding(12)
                                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                                                .cornerRadius(8)
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            // Expand all domains by default
                            let domains = Set(computers.prefix(20).map { $0.emailDomain })
                            expandedDomains = domains
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .background(Color.clear)
        } // end else (not loading)
        } // end Group
        .task { await refreshDashboard() }
        
        // MARK: - Sheets
        .sheet(isPresented: $showCategorySheet) {
            VStack(spacing: 20) {
                Text(categoryToEdit == nil ? "New Category" : "Edit Category").font(.headline)
                TextField("Category Name", text: $categoryNameInput)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                    .onSubmit { Task { await saveCategory() } }

                if let categorySaveError {
                    Label(categorySaveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(width: 300)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Cancel") { showCategorySheet = false }
                        .keyboardShortcut(.escape, modifiers: [])
                    Button("Save") { Task { await saveCategory() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(categoryNameInput.isEmpty || isSaving)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding().frame(width: 350, height: 200)
        }
        .confirmationDialog("Delete Category?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete '\(categoryToDelete?.name ?? "")'", role: .destructive) {
                if let cat = categoryToDelete { Task { await deleteCategory(cat) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will verify if the category is empty before deletion.")
        }
        .sheet(isPresented: $showExportProgress) {
            ExportProgressSheet(isPresented: $showExportProgress, progress: exportProgress)
        }
    }
    
    // MARK: - Actions
    
    func refreshDashboard() async {
        isLoading = true
        isLoadingInstallomator = true
        isLoadingUnused = true

        // Each count stands or falls on its own. These were previously awaited as a single tuple,
        // so one failure — a throttled request, or the Platform API refusing a Blueprints read —
        // left every tile reading zero. Now a section that could not be read shows "—" and the
        // rest of the dashboard still fills in.
        async let fetchedComputers = api.fetchDashboardComputers()
        async let fetchedProfiles = api.fetchProfiles()
        async let fetchedScripts = api.fetchScripts()
        async let fetchedPolicies = api.fetchPolicies()
        async let fetchedCategories = api.fetchCategories()
        async let fetchedPackages = api.fetchJamfPackages()

        let comps = try? await fetchedComputers
        let profs = try? await fetchedProfiles
        let scripts = try? await fetchedScripts
        let pols = try? await fetchedPolicies
        let cats = try? await fetchedCategories
        let packages = try? await fetchedPackages
        let blueprints = await loadBlueprintCount()

        computerCount = comps?.count
        profileCount = profs?.count
        scriptCount = scripts?.count
        policyCount = pols?.count
        packageCount = packages?.count
        blueprintCount = blueprints

        // A failed read leaves the last good list in place rather than replacing it with an empty
        // one, which would claim the estate is empty when it is only unreachable.
        if let comps { computers = comps }
        if let cats { categories = cats.sorted { $0.name < $1.name } }

        isLoading = false

        if !hasReportedInitialLoad {
            hasReportedInitialLoad = true
            onInitialLoadFinished()
        }

        // Deliberately after the Dashboard is on screen and the launch overlay has been dismissed.
        // The Unused count costs a scan of every policy in the tenant — tens of seconds on a large
        // instance, and the most expensive thing this app does. Awaiting it above would have moved
        // that cost onto every launch before anything was usable.
        await loadHeadlineTiles(profiles: profs, packages: packages, categories: cats)
    }

    /// The two tiles that cannot be answered by a list fetch, loaded together once the rest of the
    /// Dashboard is already up. Leaving the module cancels them, which is the right outcome: an
    /// abandoned scan is waste, and the tiles are rebuilt on the way back in.
    private func loadHeadlineTiles(profiles: [ConfigProfile]?,
                                   packages: [JamfPackage]?,
                                   categories: [Category]?) async {
        async let installomator: Void = loadInstallomatorTile()
        async let unused: Void = loadUnusedTile(profiles: profiles,
                                                packages: packages,
                                                categories: categories)
        _ = await (installomator, unused)
    }

    /// Label count from Installomator's published list, and when that list last changed.
    ///
    /// The two are separate requests to separate GitHub hosts and either can fail on its own, so
    /// they are read concurrently and the tile shows whichever it got. No date is better than a
    /// wrong one; no count means the tile reads as unavailable, exactly as the Jamf tiles do.
    private func loadInstallomatorTile() async {
        async let labels = try? api.fetchInstallomatorLabelsFromGitHub()
        async let updated = api.fetchInstallomatorLabelsUpdated()

        let (fetchedLabels, fetchedUpdated) = await (labels, updated)
        installomatorLabelCount = fetchedLabels?.count
        installomatorLabelsUpdated = fetchedUpdated
        isLoadingInstallomator = false
    }

    /// How many objects the Unused audit would list.
    ///
    /// Reuses the profiles, packages and categories the Dashboard has already fetched, so the extra
    /// cost of this tile is one `scanPolicyEstate` rather than a second copy of four fetches. The
    /// audit rules live in `RedundantAudit` and are not duplicated here — a headline that disagreed
    /// with the module it links to would be worse than no headline.
    private func loadUnusedTile(profiles: [ConfigProfile]?,
                                packages: [JamfPackage]?,
                                categories: [Category]?) async {
        defer { isLoadingUnused = false }

        // Any of the three missing means the Dashboard's own read already failed. The tile says
        // "unavailable" rather than counting an audit built on a partial estate.
        guard let profiles, let packages, let categories else { return }

        // Widens Installomator detection past "the policy's script is called Installomator", as the
        // Unused module does. A failure here only narrows detection.
        let knownScriptIDs = (try? await api.fetchInstallomatorScriptIDs()) ?? []
        guard let estate = try? await api.scanPolicyEstate(knownScriptIDs: knownScriptIDs) else {
            return
        }

        let categoryNames = Dictionary(
            categories.map { (String($0.id), $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        unusedCount = RedundantAudit.items(
            policies: estate.policies,
            profiles: profiles,
            packages: packages,
            packageUsage: estate.packageUsage,
            installomatorPolicyIDs: Set(estate.installomator.map(\.policyID)),
            categoryNames: categoryNames
        ).count
    }

    /// Blueprints are served by the Platform API, which uses its own credentials (see
    /// `PlatformAPISession`). Without them the request could only fail, so it is not made: the tile
    /// shows no value and still navigates to the module, where the credentials can be set up.
    private func loadBlueprintCount() async -> Int? {
        guard api.isPlatformConfigured else { return nil }
        return try? await api.fetchBlueprints().count
    }
    
    func openCategorySheet(for category: Category?) {
        categoryToEdit = category
        categoryNameInput = category?.name ?? ""
        categorySaveError = nil
        showCategorySheet = true
    }
    
    func saveCategory() async {
        isSaving = true
        categorySaveError = nil
        do {
            if let existing = categoryToEdit {
                try await api.updateCategory(id: existing.id, newName: categoryNameInput)
            } else {
                try await api.createCategory(name: categoryNameInput)
            }
            showCategorySheet = false
            await refreshDashboard()
        } catch {
            // A failed write used to leave this sheet open with nothing said, which reads as
            // "it won't let me save". Say what happened instead — no response body in the log
            // (root CLAUDE.md, invariant 4).
            print("[Dashboard] Category save rejected by Jamf")
            categorySaveError = categoryToEdit == nil
                ? "Jamf rejected this new category. Check the name and that your API client may create categories, then try again."
                : "Jamf rejected the rename. Check the name and that your API client may update categories, then try again."
        }
        isSaving = false
    }
    
    func confirmDelete(_ category: Category) {
        categoryToDelete = category
        showDeleteConfirmation = true
    }
    
    func deleteCategory(_ category: Category) async {
        do {
            try await api.deleteCategory(id: category.id)
            await refreshDashboard()
        } catch {
            print("Failed to delete category: \(error)")
        }
    }
    
    func exportAllData() {
        isExporting = true
        exportProgress.reset()
        showExportProgress = true
        
        Task {
            _ = await ExportService.exportAllDataToZip(api: api, progress: exportProgress)
            
            // Wait a moment to show completion state
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            await MainActor.run {
                isExporting = false
                showExportProgress = false // Auto-dismiss sheet
            }
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    /// `nil` when the count could not be read — rendered as "—" rather than 0, so an unreachable
    /// section is never mistaken for an empty one.
    let count: Int?
    let icon: String
    let color: Color
    /// An optional second line under the title — what the number counts, or when it was last
    /// updated. Only the tiles that need one set it.
    var detail: String? = nil
    /// Still being read. Distinct from `count == nil`, which says the read *failed*: the tiles that
    /// cost a full estate scan fill in after the Dashboard is already up, and a dash in the meantime
    /// would report a failure that has not happened.
    var isLoading: Bool = false
    /// Roll the number up to its answer and give it one pulse when it lands.
    ///
    /// Only the two tiles that arrive late set this. The six that come back with the first load
    /// would all roll at once, which is noise rather than emphasis.
    var animatesArrival: Bool = false

    @State private var isHovering = false
    /// What the tile is currently showing while the roll-up runs. Only consulted when
    /// `animatesArrival` is set.
    @State private var displayedCount = 0
    @State private var isPulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var countText: String {
        guard let count else { return "—" }
        return String(animatesArrival ? displayedCount : count)
    }

    /// The card is an icon and two or three pieces of text, none of which names the tile on its
    /// own, so the whole card is exposed as one element with a spoken summary.
    private var accessibilitySummary: String {
        if isLoading { return "\(title), still loading" }
        guard let count else { return "\(title), count unavailable" }
        guard let detail else { return "\(title), \(count)" }
        return "\(title), \(count), \(detail)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                Spacer()
                if isLoading {
                    TileSpinner()
                        .padding(.trailing, 4)
                } else {
                    Text(countText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(count == nil ? .secondary : .primary)
                        .scaleEffect(isPulsing ? 1.18 : 1.0)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.secondary)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        // The tiles sit in one grid row, and only some carry a detail line. Without this the
        // taller ones would stand proud of their neighbours instead of the row squaring off.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .liquidGlass(cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens the \(title) section")
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { isHovering = $0 }
        // Restarts whenever the count changes, and is cancelled when the tile goes away — so a
        // half-finished roll-up on a Dashboard the reader has left simply stops.
        .task(id: count) {
            guard let count else { return }
            await rollUp(to: count)
        }
        // Declarative, and balanced by the system. The old NSCursor push/pop pair called into AppKit
        // from a hover callback — which can land inside a Core Animation commit — and popped on
        // hover-out whether or not a matching push had happened, so the cursor stack could drift.
        .pointerStyle(.link)
    }

    /// Counts the tile up to its answer, then pulses once.
    ///
    /// Every number shown on the way is between where the tile was and the figure Jamf returned, so
    /// nothing invented ever appears. That is also why there is no count climbing *during* the read:
    /// until the scan comes back nobody knows the total, and a number rising on a tile where a dash
    /// means "this failed" would be a claim rather than a flourish. The spinner says "working"; this
    /// says "here it is".
    ///
    /// Rolls from whatever is on screen rather than from zero, so a refresh moves from the old
    /// figure to the new one instead of dropping to nothing first.
    private func rollUp(to target: Int) async {
        guard animatesArrival, !reduceMotion else {
            displayedCount = target
            return
        }

        let start = displayedCount
        guard start != target else { return }

        let steps = 18
        let step = Duration.seconds(0.5 / Double(steps))

        for tick in 1...steps {
            let progress = Double(tick) / Double(steps)
            // Ease out, so it slows into the answer rather than stopping dead on it.
            let eased = 1 - pow(1 - progress, 3)
            displayedCount = start + Int((Double(target - start) * eased).rounded())
            do { try await Task.sleep(for: step) } catch { return }
        }
        displayedCount = target

        withAnimation(.spring(response: 0.26, dampingFraction: 0.4)) { isPulsing = true }
        try? await Task.sleep(for: .seconds(0.16))
        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) { isPulsing = false }
    }
}

/// The tile's "still reading" indicator, drawn in SwiftUI rather than hosted from AppKit.
///
/// `ProgressView` wraps an `NSProgressIndicator`. The card's hover `scaleEffect` re-hosts it at
/// fractional sizes — 16.498pt, then 16.495, settling back to 16.000 as the spring unwinds — and
/// AppKit logs a constraint complaint for each one, hundreds of lines deep while a tile is loading.
/// Nothing was wrong on screen; the noise buried the app's own logging. Drawing the arc here removes
/// the hosted view, and with it the message.
private struct TileSpinner: View {
    @State private var isSpinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(reduceMotion
                       ? nil
                       : .linear(duration: 0.9).repeatForever(autoreverses: false),
                       value: isSpinning)
            .onAppear { isSpinning = true }
            // The card speaks for itself — `StatCard.accessibilitySummary` already says "still
            // loading" — so the arc is decoration.
            .accessibilityHidden(true)
    }
}

struct CategoryTile: View {
    let category: Category
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Image(systemName: "folder.fill").foregroundColor(.blue)
            Text(category.name).fontWeight(.medium).lineLimit(1)
            Spacer()
            if isHovering {
                HStack(spacing: 4) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill").foregroundColor(.red.opacity(0.8))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.1), lineWidth: 1))
        .onHover { isHovering = $0 }
    }
}
struct ExportAllCard: View {
    let isExporting: Bool
    @State private var isHovering = false
    /// Counts hover *entries* only. Handing the shine `isHovering` itself would run it on the way
    /// out as well, which reads as the card twitching when you leave.
    @State private var hoverEntries = 0

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 36, height: 36)
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
            }
            
            Text(isExporting ? "Exporting..." : "Export All")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isExporting ? .secondary : .primary)
            
            Text(isExporting ? "Please wait..." : "Download Data")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .liquidGlass(cornerRadius: 12)
        .shine(isActive: !isExporting, cornerRadius: 12, tint: .green, trigger: hoverEntries)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(isHovering ? 0.5 : 0.2), lineWidth: 2)
        )
        .scaleEffect(isHovering && !isExporting ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isHovering)
        .onHover { inside in
            isHovering = inside
            // Reaching for the card is a deliberate act, so answering it is not the same as looping.
            if inside && !isExporting { hoverEntries += 1 }
        }
        .pointerStyle(isExporting ? nil : .link)
    }
}

