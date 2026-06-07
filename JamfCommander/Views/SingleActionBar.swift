//
//  SingleActionBar.swift
//  JamfCommander
//
//  Action bar shown when exactly one policy is selected. Mirrors the bulk action bar but
//  with singular wording, and "Edit Policy" opens the full inspector/editor (the same view
//  the right-click → Inspect shows).
//
//  Each action is a centred header (the action name) above a compact, icon-only tinted
//  button with the action as its tooltip. "Move to Category" opens a glass popover of
//  searchable Liquid Glass category chips. Every write is confirmed and reports a real
//  result. Built to be reusable across the app once the design is approved.
//

import SwiftUI

struct SingleActionBar: View {
    @ObservedObject var api: JamfAPIService

    let policy: Policy
    let categories: [Category]

    @Binding var isBusy: Bool
    @Binding var statusMessage: String

    /// Opens the full inspector/editor for the policy id.
    var onEdit: (Int) -> Void
    var onClearSelection: () -> Void
    var onRefresh: () async -> Void

    @State private var confirmation: ConfirmationData?
    @State private var resultsLog: [OperationResult] = []
    @State private var showResultsSheet = false

    @State private var showMovePopover = false
    @State private var categorySearch = ""

    @State private var showCloneSheet = false
    @State private var bulkClonePlan: [BulkClonePlanItem] = []
    @State private var bulkCloneConfig: BulkCloneConfig?
    @State private var mutableCategories: [Category] = []

    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    var body: some View {
        HStack(spacing: 16) {
            leftInfo

            Divider()

            actionColumn("Move to Category") { moveButton }

            Divider()

            actionColumn("Match Self Service Category") {
                iconButton("arrow.triangle.2.circlepath", tint: .teal, help: "Match Self Service Category") {
                    requestMatchSelfService()
                }
            }

            Divider()

            actionColumn("Edit Policy") {
                iconButton("slider.horizontal.3", tint: .blue, help: "Edit this policy") {
                    onEdit(policy.id)
                }
            }

            Divider()

            actionColumn("Clone Policy") {
                iconButton("doc.on.doc", tint: .purple, help: "Clone this policy") {
                    showCloneSheet = true
                }
            }

            Divider()

            actionColumn("Delete Policy") {
                iconButton("trash.fill", tint: .red, role: .destructive, help: "Delete this policy") {
                    requestDelete()
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
            BulkCloneSheet(
                api: api,
                categories: mutableCategories,
                policies: [policy],
                onConfirm: { plan, config in
                    bulkClonePlan = plan
                    bulkCloneConfig = config
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
            Label("Policy", systemImage: "scroll.fill")
                .font(.headline)
                .foregroundColor(.primary)

            Text(policy.name)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Text("ID: \(policy.id)")
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

    /// Centred action-name header above its control.
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

    /// Compact, icon-only tinted action button with a tooltip.
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
        .help("Move this policy to a category")
        .popover(isPresented: $showMovePopover, arrowEdge: .top) {
            moveCategoryPopover
        }
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
                    GlassEffectContainer(spacing: 8) {
                        FlowLayout(spacing: 8, alignment: .leading) {
                            ForEach(filteredCategories) { category in
                                Button {
                                    showMovePopover = false
                                    requestMove(to: category)
                                } label: {
                                    Text(category.name)
                                        .font(.callout)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                        .padding(2)
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    // MARK: - Actions

    private func requestMove(to category: Category) {
        confirmation = ConfirmationData(
            title: "Confirm Move",
            message: "Move '\(policy.name)' to the '\(category.name)' category?",
            actionTitle: "Move",
            role: .none,
            action: { performMove(to: category) }
        )
    }

    private func performMove(to category: Category) {
        isBusy = true
        statusMessage = "Moving…"
        resultsLog = []
        Task {
            let result: OperationResult
            do {
                try await api.movePolicy(id: policy.id, toCategoryID: category.id, categoryName: category.name)
                result = OperationResult(
                    itemName: policy.name, success: true, error: nil,
                    fromCategory: policy.categoryName ?? "No Category", toCategory: category.name
                )
            } catch {
                result = OperationResult(itemName: policy.name, success: false, error: "\(error)")
            }
            await MainActor.run {
                resultsLog = [result]
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }

    private func requestMatchSelfService() {
        guard let categoryId = policy.categoryId, categoryId != -1,
              let categoryName = policy.categoryName, !categoryName.isEmpty else {
            confirmation = ConfirmationData(
                title: "No Main Category",
                message: "This policy has no main category, so there's nothing to match its Self Service category to.",
                actionTitle: "OK",
                role: .none,
                action: {}
            )
            return
        }
        confirmation = ConfirmationData(
            title: "Match Self Service Category",
            message: "Set the Self Service category for '\(policy.name)' to match its main category '\(categoryName)'?",
            actionTitle: "Match",
            role: .none,
            action: { performMatchSelfService(categoryId: categoryId, categoryName: categoryName) }
        )
    }

    private func performMatchSelfService(categoryId: Int, categoryName: String) {
        isBusy = true
        statusMessage = "Matching…"
        resultsLog = []
        Task {
            let result: OperationResult
            do {
                try await api.setPolicySelfServiceCategory(id: policy.id, toCategoryID: categoryId, categoryName: categoryName)
                result = OperationResult(itemName: policy.name, success: true, error: nil, toCategory: "SS → \(categoryName)")
            } catch {
                result = OperationResult(itemName: policy.name, success: false, error: "\(error)")
            }
            await MainActor.run {
                resultsLog = [result]
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }

    private func requestDelete() {
        let url = instanceURL.isEmpty ? "your Jamf instance" : instanceURL
        confirmation = ConfirmationData(
            title: "⚠️ Confirm Deletion",
            message: "You are about to DELETE '\(policy.name)' from \(url).\n\nThis cannot be undone. Please confirm.",
            actionTitle: "Delete Forever",
            role: .destructive,
            action: { performDelete() }
        )
    }

    private func performDelete() {
        isBusy = true
        statusMessage = "Deleting…"
        resultsLog = []
        Task {
            let result: OperationResult
            do {
                try await api.deletePolicy(id: policy.id)
                result = OperationResult(itemName: policy.name, success: true, error: nil)
            } catch {
                result = OperationResult(itemName: policy.name, success: false, error: "\(error)")
            }
            await MainActor.run {
                resultsLog = [result]
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }

    private func requestClone() {
        guard let config = bulkCloneConfig else { return }
        let url = instanceURL.isEmpty ? "your Jamf instance" : instanceURL
        confirmation = ConfirmationData(
            title: "Confirm Clone",
            message: "Clone '\(policy.name)' into '\(config.targetCategoryName)' on \(url)?\n\nThe clone is created disabled. Please confirm.",
            actionTitle: "Clone Policy",
            role: .none,
            action: { performClone() }
        )
    }

    private func performClone() {
        guard let config = bulkCloneConfig else { return }
        isBusy = true
        statusMessage = "Cloning…"
        resultsLog = []
        Task {
            let results = await api.bulkClonePolicies(bulkClonePlan, config: config)
            await MainActor.run {
                resultsLog = results
                isBusy = false
                statusMessage = "Done."
                showResultsSheet = true
            }
        }
    }
}
