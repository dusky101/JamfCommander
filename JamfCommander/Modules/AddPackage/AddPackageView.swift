//
//  AddPackageView.swift
//  JamfCommander
//
//  The Add PKG module: uploading a package Installomator has no label for, and seeing the packages
//  Jamf already holds.
//
//  Three tabs, laid out like the Installomator manager so the two read as one app:
//
//  · **New** — the upload flow (`PackageUploadPage`).
//  · **Uploaded** — every package in Jamf's library.
//  · **Deployed** — only those a policy actually installs.
//
//  This view owns the data all three share: the categories, computers and groups the upload form
//  needs, the package library, and the package → policy map behind the Deployed tab. That map is the
//  expensive one — Jamf has no reverse lookup, so every policy has to be read — so it is fetched once,
//  lazily, the first time a library tab is opened, and never for the New tab alone.
//

import SwiftUI

struct AddPackageView: View {
    @ObservedObject var api: JamfAPIService

    @State private var tab: AddPackageTab = .new

    // Shared reference data (the upload form needs all of it; the library needs the categories).
    @State private var categories: [Category] = []
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var computerGroups: [ComputerGroup] = []
    @State private var existingPackageNameKeys: Set<String> = []
    @State private var existingPolicyNameKeys: Set<String> = []
    @State private var nameCheckFailed = false
    @State private var jamfProVersion: String?
    @State private var isLoading = true
    @State private var loadFailed = false

    // The library
    @State private var packages: [JamfPackage] = []
    @State private var packageUsage: [String: [String]] = [:]
    @State private var isLoadingPackages = false
    @State private var packagesLoadFailed = false
    @State private var isScanningUsage = false
    @State private var usageScanFailed = false
    @State private var hasScannedUsage = false

    @State private var libraryGroupMode: PackageGroupMode = .alphabetical
    @State private var librarySearchText = ""

    /// Which of the module's three pages is showing.
    enum AddPackageTab: String, CaseIterable, Identifiable {
        case new = "New"
        case uploaded = "Uploaded"
        case deployed = "Deployed"

        var id: String { rawValue }

        var isLibrary: Bool { self != .new }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .toolbar {
            // These were fixed-width Pickers in the header row, which could not compress: below
            // roughly 1100pt the row's minimum exceeded its pane, the title wrapped onto three
            // lines and the content overflowed the right edge. Toolbar items collapse into an
            // overflow menu instead of overflowing.
            if tab.isLibrary {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Group", selection: $libraryGroupMode) {
                        ForEach(PackageGroupMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Group the list alphabetically or by category")
                }
            }

            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    Text(AddPackageTab.new.rawValue).tag(AddPackageTab.new)
                    Text(uploadedTabLabel).tag(AddPackageTab.uploaded)
                    Text(deployedTabLabel).tag(AddPackageTab.deployed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("New uploads a package; Uploaded lists Jamf's package library; Deployed lists only the packages a policy installs.")
            }

            if tab.isLibrary {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reloadLibrary() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Reload the package library")
                    .disabled(isLoadingPackages || isScanningUsage)
                }
            }
        }
        .task { await loadReferenceData() }
        .onChange(of: tab) {
            // The library — and especially the policy scan behind it — is only worth fetching once
            // somebody actually asks to see it.
            if tab.isLibrary { Task { await loadLibraryIfNeeded() } }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Package Manager")
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if let jamfProVersion, tab == .new {
                Text("Jamf Pro \(jamfProVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidGlassCapsule()
                    .fixedSize()
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var subtitle: String {
        switch tab {
        case .new: return "Upload a package Installomator has no label for, and create its install policy."
        case .uploaded: return "Every package in this Jamf instance."
        case .deployed: return "Packages a policy installs."
        }
    }

    private var uploadedTabLabel: String {
        packages.isEmpty ? "Uploaded" : "Uploaded (\(packages.count))"
    }

    /// An ellipsis until the scan has actually answered: a zero here would read as "nothing is
    /// deployed", which is a very different claim from "not counted yet".
    private var deployedTabLabel: String {
        guard hasScannedUsage else { return isScanningUsage ? "Deployed (…)" : "Deployed" }
        return "Deployed (\(deployedPackages.count))"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .new:
            if isLoading {
                LoadingProgressView(message: "Loading Jamf data...")
            } else if loadFailed {
                loadErrorView
            } else {
                PackageUploadPage(
                    api: api,
                    categories: categories,
                    computers: computers,
                    computerGroups: computerGroups,
                    existingPackageNameKeys: existingPackageNameKeys,
                    existingPolicyNameKeys: existingPolicyNameKeys,
                    nameCheckFailed: nameCheckFailed,
                    onCategoriesReloaded: { categories = $0 },
                    onUploadFinished: {
                        Task {
                            await loadNameIndexes()
                            // A package has just arrived, so anything already loaded is out of date.
                            if hasLoadedLibrary { await reloadLibrary() }
                        }
                    }
                )
            }

        case .uploaded:
            libraryView(
                packages: packages,
                emptyTitle: "No packages in Jamf",
                emptyDetail: "This instance has no packages yet. Upload one from the New tab."
            )

        case .deployed:
            libraryView(
                packages: deployedPackages,
                emptyTitle: hasScannedUsage ? "No packages are attached to a policy" : "Checking policies",
                emptyDetail: hasScannedUsage
                    ? "Every package in Jamf's library exists without a policy installing it. The Uploaded tab lists them."
                    : "Reading every policy to see which packages they install."
            )
        }
    }

    @ViewBuilder
    private func libraryView(packages: [JamfPackage], emptyTitle: String, emptyDetail: String) -> some View {
        if isLoadingPackages {
            LoadingProgressView(message: "Loading packages from Jamf...")
        } else if packagesLoadFailed {
            packagesErrorView
        } else {
            JamfPackageLibraryView(
                packages: packages,
                usage: packageUsage,
                categoryNames: categoryNamesByID,
                isScanning: isScanningUsage,
                scanFailed: usageScanFailed,
                groupMode: $libraryGroupMode,
                searchText: $librarySearchText,
                emptyTitle: emptyTitle,
                emptyDetail: emptyDetail
            )
        }
    }

    private var loadErrorView: some View {
        errorView(
            title: "Couldn't load the Jamf data for this page",
            detail: "Categories, computers and groups are needed before a package can be filed and scoped. Check your connection to Jamf and try again — nothing has been uploaded.",
            retry: { Task { await loadReferenceData() } }
        )
    }

    private var packagesErrorView: some View {
        errorView(
            title: "Couldn't load the package library",
            detail: "Jamf's package list could not be read. Check your connection and that this API client has the 'Read Packages' privilege, then try again.",
            retry: { Task { await reloadLibrary() } }
        )
    }

    private func errorView(title: String, detail: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                // Bounded for the same reason as the library's empty state: this sits outside a
                // ScrollView, so an unbounded fixedSize can push the module past the window.
                .frame(maxWidth: 420)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived

    /// Jamf category id → name. The package list carries ids; every row and the category grouping
    /// want names.
    private var categoryNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: categories.map { (String($0.id), $0.name) })
    }

    private var deployedPackages: [JamfPackage] {
        packages.filter { !(packageUsage[$0.id] ?? []).isEmpty }
    }

    private var hasLoadedLibrary: Bool { !packages.isEmpty || packagesLoadFailed }

    // MARK: - Loading

    private func loadReferenceData() async {
        isLoading = true
        loadFailed = false

        do {
            async let categoriesResult = api.fetchCategories()
            async let computersResult = api.fetchComputers()
            async let groupsResult = api.fetchComputerGroups()

            // Advisory: the version only labels the page, and a failure to read it changes nothing.
            let version = try? await api.fetchJamfProVersion()
            let (fetchedCategories, fetchedComputers, fetchedGroups) =
                try await (categoriesResult, computersResult, groupsResult)

            await MainActor.run {
                categories = fetchedCategories.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                computers = fetchedComputers
                computerGroups = fetchedGroups.sorted { lhs, rhs in
                    if lhs.smartGroup != rhs.smartGroup { return lhs.smartGroup == true }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                jamfProVersion = version
                isLoading = false
            }

            await loadNameIndexes()
        } catch {
            // Deliberately no error body in the log — see root CLAUDE.md, invariant 4.
            print("[Packages] Add Package page data load failed")
            await MainActor.run {
                isLoading = false
                loadFailed = true
            }
        }
    }

    /// The package and policy names already in Jamf, for the upload page's pre-flight checks.
    /// Advisory: if either read fails the page still works, and Jamf reports the clash itself.
    private func loadNameIndexes() async {
        let packageNames = try? await api.fetchPackageNames()
        let policyNames = try? await api.fetchPolicyNames()

        await MainActor.run {
            existingPackageNameKeys = Set((packageNames ?? []).map(PolicyNameMatching.exactKey))
            existingPolicyNameKeys = Set((policyNames ?? []).map(PolicyNameMatching.exactKey))
            nameCheckFailed = packageNames == nil
        }
    }

    /// Loads the library the first time a library tab is opened, then leaves it alone until something
    /// changes it or Refresh is pressed.
    private func loadLibraryIfNeeded() async {
        guard !hasLoadedLibrary, !isLoadingPackages else { return }
        await reloadLibrary()
    }

    private func reloadLibrary() async {
        isLoadingPackages = true
        packagesLoadFailed = false

        do {
            let fetched = try await api.fetchJamfPackages()
            await MainActor.run {
                packages = fetched
                isLoadingPackages = false
            }
        } catch {
            print("[Packages] Package library load failed")
            await MainActor.run {
                packages = []
                isLoadingPackages = false
                packagesLoadFailed = true
            }
            return
        }

        await scanPackageUsage()
    }

    /// The expensive half: every policy is read to find out which packages it installs. Run after the
    /// list is already on screen, so the library is usable while the deployed state fills in.
    private func scanPackageUsage() async {
        await MainActor.run {
            isScanningUsage = true
            usageScanFailed = false
        }

        do {
            let usage = try await api.fetchPackagePolicyUsage()
            await MainActor.run {
                packageUsage = usage
                hasScannedUsage = true
                isScanningUsage = false
            }
        } catch {
            print("[Packages] Package usage scan failed")
            await MainActor.run {
                packageUsage = [:]
                hasScannedUsage = false
                isScanningUsage = false
                usageScanFailed = true
            }
        }
    }
}
