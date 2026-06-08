//
//  SingleActionBar.swift
//  JamfCommander
//
//  Action bar shown when exactly one policy is selected. Mirrors the bulk action bar but
//  with singular wording, and "Edit Policy" opens the full inspector/editor (the same view
//  the right-click → Inspect shows).
//
//  Uses the shared action-bar components (centred header + soft tinted icon button) and the
//  blue category popover. Every write is confirmed and reports a real result.
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

    @State private var showCloneSheet = false
    @State private var bulkClonePlan: [BulkClonePlanItem] = []
    @State private var bulkCloneConfig: BulkCloneConfig?
    @State private var mutableCategories: [Category] = []

    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    var body: some View {
        HStack(spacing: 16) {
            leftInfo

            Divider()

            ActionBarColumn(title: "Move to Category") { moveButton }

            Divider()

            ActionBarColumn(title: "Match Self Service Category") {
                SoftIconButton(systemImage: "arrow.triangle.2.circlepath", tint: .teal, isDisabled: isBusy, help: "Match Self Service Category") {
                    requestMatchSelfService()
                }
            }

            Divider()

            ActionBarColumn(title: "Edit Policy") {
                SoftIconButton(systemImage: "slider.horizontal.3", tint: .blue, isDisabled: isBusy, help: "Edit this policy") {
                    onEdit(policy.id)
                }
            }

            Divider()

            ActionBarColumn(title: "Clone Policy") {
                SoftIconButton(systemImage: "doc.on.doc", tint: .purple, isDisabled: isBusy, help: "Clone this policy") {
                    showCloneSheet = true
                }
            }

            Divider()

            ActionBarColumn(title: "Delete Policy") {
                SoftIconButton(systemImage: "trash.fill", tint: .red, role: .destructive, isDisabled: isBusy, help: "Delete this policy") {
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

    private var moveButton: some View {
        Button { showMovePopover = true } label: {
            SoftIconLabel(systemImage: "folder", tint: .indigo)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || categories.isEmpty)
        .help("Move this policy to a category")
        .popover(isPresented: $showMovePopover, arrowEdge: .top) {
            CategoryMovePicker(categories: categories) { category in
                showMovePopover = false
                requestMove(to: category)
            }
        }
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
