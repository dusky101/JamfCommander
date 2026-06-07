//
//  SingleProfileActionBar.swift
//  JamfCommander
//
//  Single-item action bar for Configuration Profiles — the profile counterpart to
//  SingleActionBar (policies). Same look (centred action-name headers + compact icon-only
//  buttons + the blue category popover), with the profile action set: Move to Category,
//  Set Scope, Edit Profile (opens the inspector), Clone Profile, Delete Profile. Every
//  write is confirmed and reports a real result.
//

import SwiftUI

struct SingleProfileActionBar: View {
    @ObservedObject var api: JamfAPIService

    let profile: ConfigProfile
    let categories: [Category]

    @Binding var isBusy: Bool
    @Binding var statusMessage: String

    /// Opens the full inspector for the profile id.
    var onEdit: (Int) -> Void
    var onClearSelection: () -> Void
    var onRefresh: () async -> Void

    @State private var confirmation: ConfirmationData?
    @State private var resultsLog: [OperationResult] = []
    @State private var showResultsSheet = false

    @State private var showMovePopover = false
    @State private var categorySearch = ""
    @State private var chipsContentHeight: CGFloat = 120

    @State private var showCloneSheet = false
    @State private var cloneConfig: CloneConfiguration?
    @State private var mutableCategories: [Category] = []

    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    var body: some View {
        HStack(spacing: 16) {
            leftInfo

            Divider()

            actionColumn("Move to Category") { moveButton }

            Divider()

            actionColumn("Set Scope") { scopeButton }

            Divider()

            actionColumn("Edit Profile") {
                iconButton("slider.horizontal.3", tint: .blue, help: "Edit this profile") {
                    onEdit(profile.id)
                }
            }

            Divider()

            actionColumn("Clone Profile") {
                iconButton("doc.on.doc", tint: .purple, help: "Clone this profile") {
                    showCloneSheet = true
                }
            }

            Divider()

            actionColumn("Delete Profile") {
                iconButton("trash.fill", tint: .red, role: .destructive, help: "Delete this profile") {
                    requestDelete()
                }
            }
        }
        .padding(20)
        .appBarBackground(cornerRadius: 16)
        .padding(.horizontal)
        .padding(.bottom, 10)
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showResultsSheet) {
            OperationResultView(
                title: "Operation Complete",
                results: resultsLog,
                onDismiss: {
                    showResultsSheet = false
                    onClearSelection()
                    Task { await onRefresh() }
                }
            )
        }
        .sheet(isPresented: $showCloneSheet) {
            CloneConfigSheet(
                api: api,
                mode: .profiles,
                itemCount: 1,
                categories: $mutableCategories,
                onConfirm: { config in
                    cloneConfig = config
                    showCloneSheet = false
                    requestClone()
                }
            )
        }
        .onAppear { mutableCategories = categories }
    }

    // MARK: - Pieces

    private var leftInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Profile", systemImage: "doc.text.fill")
                .font(.headline)
                .foregroundColor(.primary)

            Text(profile.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Text("ID: \(profile.id)")
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { withAnimation { onClearSelection() } }) {
                Label("Cancel Selection", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .frame(width: 150, alignment: .leading)
    }

    private func actionColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            content()
        }
        .frame(maxWidth: .infinity)
    }

    private func iconButton(_ systemImage: String, tint: Color, role: ButtonRole? = nil, help: String, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 60, height: 38)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .disabled(isBusy)
        .help(help)
    }

    private var moveButton: some View {
        Button { showMovePopover = true } label: {
            Image(systemName: "folder")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 60, height: 38)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .controlSize(.large)
        .disabled(isBusy || categories.isEmpty)
        .help("Move this profile to a category")
        .popover(isPresented: $showMovePopover, arrowEdge: .top) {
            moveCategoryPopover
        }
    }

    private var scopeButton: some View {
        Menu {
            Button { requestScopeAllComputers() } label: { Label("Scope to All Computers", systemImage: "globe") }
            Button(role: .destructive) { requestRemoveScope() } label: { Label("Remove Scope", systemImage: "xmark.circle") }
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 60, height: 38)
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(isBusy)
        .help("Set this profile's scope")
    }

    private var filteredCategories: [Category] {
        let query = categorySearch.trimmingCharacters(in: .whitespaces)
        let base = query.isEmpty ? categories : categories.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var moveCategoryPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move to Category")
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search categories", text: $categorySearch)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            if filteredCategories.isEmpty {
                Text("No categories match “\(categorySearch)”.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    FlowLayout(spacing: 8, alignment: .leading) {
                        ForEach(filteredCategories) { category in
                            categoryChip(category)
                        }
                    }
                    .padding(2)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        chipsContentHeight = newHeight
                    }
                }
                .frame(height: min(chipsContentHeight + 4, 480))
            }
        }
        .padding(16)
        .frame(width: 600)
    }

    private func categoryChip(_ category: Category) -> some View {
        Button {
            showMovePopover = false
            requestMove(to: category)
        } label: {
            Text(category.name)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(Color.blue)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Move to “\(category.name)”")
    }

    // MARK: - Actions

    private func requestMove(to category: Category) {
        confirmation = ConfirmationData(
            title: "Confirm Move",
            message: "Move '\(profile.name)' to the '\(category.name)' category?",
            actionTitle: "Move",
            role: .none,
            action: { performMove(to: category) }
        )
    }

    private func performMove(to category: Category) {
        runWrite(status: "Moving…", successResult: OperationResult(
            itemName: profile.name, success: true, error: nil,
            fromCategory: profile.categoryName, toCategory: category.name
        )) {
            try await self.api.moveProfile(self.profile.id, toCategoryID: category.id)
        }
    }

    private func requestScopeAllComputers() {
        confirmation = ConfirmationData(
            title: "Confirm Scope Change",
            message: "Set '\(profile.name)' to deploy to All Computers?",
            actionTitle: "Scope to All",
            role: .none,
            action: {
                runWrite(status: "Updating scope…",
                         successResult: OperationResult(itemName: profile.name, success: true, error: nil, toCategory: "Scope: All Computers")) {
                    try await self.api.setProfileScopeToAllComputers(self.profile.id)
                }
            }
        )
    }

    private func requestRemoveScope() {
        confirmation = ConfirmationData(
            title: "Confirm Scope Change",
            message: "Remove all scope from '\(profile.name)'? It will no longer be deployed to any computers.",
            actionTitle: "Remove Scope",
            role: .destructive,
            action: {
                runWrite(status: "Updating scope…",
                         successResult: OperationResult(itemName: profile.name, success: true, error: nil, toCategory: "Scope: Removed")) {
                    try await self.api.removeProfileScope(self.profile.id)
                }
            }
        )
    }

    private func requestDelete() {
        let url = instanceURL.isEmpty ? "your Jamf instance" : instanceURL
        confirmation = ConfirmationData(
            title: "⚠️ Confirm Deletion",
            message: "You are about to DELETE '\(profile.name)' from \(url).\n\nThis cannot be undone. Please confirm.",
            actionTitle: "Delete Forever",
            role: .destructive,
            action: {
                runWrite(status: "Deleting…",
                         successResult: OperationResult(itemName: profile.name, success: true, error: nil)) {
                    try await self.api.deleteProfile(id: self.profile.id)
                }
            }
        )
    }

    private func requestClone() {
        guard let config = cloneConfig else { return }
        let categoryName = mutableCategories.first(where: { $0.id == config.targetCategoryID })?.name ?? "the selected category"
        confirmation = ConfirmationData(
            title: "Confirm Clone",
            message: "Clone '\(profile.name)' into '\(categoryName)'?\n\nNew profile will be named 'Copy of \(profile.name)'. Please confirm.",
            actionTitle: "Clone Profile",
            role: .none,
            action: { performClone(config: config) }
        )
    }

    private func performClone(config: CloneConfiguration) {
        isBusy = true
        statusMessage = "Cloning…"
        resultsLog = []
        let cloneName = "Copy of \(profile.name)"
        Task {
            let result: OperationResult
            do {
                let newId = try await api.cloneProfile(id: profile.id, newName: cloneName, toCategoryID: config.targetCategoryID, stripScope: config.stripScope)
                result = OperationResult(itemName: cloneName, success: true, error: nil, toCategory: "Created (ID: \(newId))")
            } catch {
                result = OperationResult(itemName: cloneName, success: false, error: "\(error)")
            }
            await MainActor.run {
                resultsLog = [result]
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }

    /// Runs a single write, reporting `successResult` on success or a failure result with
    /// the error, then surfaces the result sheet.
    private func runWrite(status: String, successResult: OperationResult, _ work: @escaping () async throws -> Void) {
        isBusy = true
        statusMessage = status
        resultsLog = []
        Task {
            let result: OperationResult
            do {
                try await work()
                result = successResult
            } catch {
                result = OperationResult(itemName: profile.name, success: false, error: "\(error)")
            }
            await MainActor.run {
                resultsLog = [result]
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }
}
