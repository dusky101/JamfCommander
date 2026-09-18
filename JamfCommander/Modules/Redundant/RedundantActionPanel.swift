//
//  RedundantActionPanel.swift
//  JamfCommander
//
//  The Redundant audit's bulk action bar, shown in place of the filter bar once something is
//  selected — the same swap `PoliciesDashboardView` makes between `FilterBar` and `ActionPanelView`.
//
//  It is a separate view rather than a mode on `ActionPanelView` because that one is typed to a
//  single domain: `[Policy]` or `[ConfigProfile]`, selected by `Set<Int>`. This audit mixes policies,
//  profiles and packages in one list, whose ids are only unique per kind. It borrows every piece the
//  other bar is built from — `ActionBarColumn`, `SoftIconButton`, `CategoryMovePicker`,
//  `appBarBackground` — so the two read as the same control.
//
//  Ordered by consequence, gentlest first: moving something to a category can be undone by hand,
//  disabling a policy can be reversed with one click, deleting cannot be undone at all.
//

import SwiftUI

struct RedundantActionPanel: View {
    let categories: [Category]
    let selectedItems: [RedundantItem]
    let isBusy: Bool

    var onClearSelection: () -> Void
    /// Called once the administrator has confirmed. The host performs the write.
    var onConfirmedAction: (JamfAPIService.RedundantAction, [RedundantItem]) -> Void

    @State private var confirmation: ConfirmationData?
    @State private var showMovePopover = false

    /// Only policies that are currently enabled have anything to disable.
    private var disableableItems: [RedundantItem] {
        selectedItems.filter(\.canBeDisabled)
    }

    private var policyCount: Int { selectedItems.filter { $0.kind == .policy }.count }
    private var profileCount: Int { selectedItems.filter { $0.kind == .profile }.count }

    var body: some View {
        HStack(spacing: 16) {
            // MARK: - Left: Selection Info
            VStack(alignment: .leading, spacing: 6) {
                Label("Redundant Actions", systemImage: "checklist")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("\(selectedItems.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)

                // Says what is actually in hand: the three actions do different things to each kind,
                // and "12 selected" on its own does not tell you that.
                Text(selectionBreakdown)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

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

            // MARK: - Move to Category (the reversible one, so it leads)
            ActionBarColumn(title: "Move to Category") {
                Button { showMovePopover = true } label: {
                    SoftIconLabel(systemImage: "folder", tint: .indigo)
                }
                .buttonStyle(.plain)
                .disabled(isBusy || categories.isEmpty || selectedItems.isEmpty)
                .help("File the selected policies and profiles under a category — nothing is deleted and nothing stops running")
                .popover(isPresented: $showMovePopover, arrowEdge: .top) {
                    CategoryMovePicker(categories: categories) { category in
                        showMovePopover = false
                        requestMove(to: category)
                    }
                }
            }

            Divider()

            // MARK: - Disable (policies only)
            ActionBarColumn(title: "Disable (\(disableableItems.count))") {
                SoftIconButton(
                    systemImage: "pause.circle.fill",
                    tint: .orange,
                    isDisabled: isBusy || disableableItems.isEmpty,
                    help: disableableItems.isEmpty
                        ? "Only policies that are currently enabled can be disabled. Jamf configuration profiles have no enabled state."
                        : "Stop the selected policies running. They stay in Jamf with their scope and payload intact."
                ) {
                    requestDisable()
                }
            }

            Divider()

            // MARK: - Danger Zone
            ActionBarColumn(title: "Delete Selection") {
                SoftIconButton(
                    systemImage: "trash.fill",
                    tint: .red,
                    role: .destructive,
                    isDisabled: isBusy || selectedItems.isEmpty,
                    help: "Permanently remove the selected policies and profiles from Jamf"
                ) {
                    requestDelete()
                }
            }
        }
        .padding(20)
        .appBarBackground(cornerRadius: 16)
        .padding(.horizontal)
        .padding(.bottom, 10)
        .commanderConfirmation(data: $confirmation)
    }

    // MARK: - Copy

    private var selectionBreakdown: String {
        var parts: [String] = []
        if policyCount > 0 { parts.append("\(policyCount) polic\(policyCount == 1 ? "y" : "ies")") }
        if profileCount > 0 { parts.append("\(profileCount) profile\(profileCount == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing actionable selected" : parts.joined(separator: ", ")
    }

    // MARK: - Confirmations
    //
    // Every one names the exact count and says plainly what will and will not change. None of these
    // actions runs without passing through here first.

    private func requestMove(to category: Category) {
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        confirmation = ConfirmationData(
            title: "Move \(targets.count) item\(targets.count == 1 ? "" : "s") to \(category.name)?",
            message: "\(selectionBreakdown) will be filed under \(category.name). Nothing is deleted, nothing is disabled, and nothing stops running. A policy's Self Service category is updated to match.",
            actionTitle: "Move \(targets.count)",
            role: nil,
            action: {
                onConfirmedAction(.moveToCategory(id: category.id, name: category.name), targets)
            }
        )
    }

    private func requestDisable() {
        let targets = disableableItems
        guard !targets.isEmpty else { return }

        confirmation = ConfirmationData(
            title: "Disable \(targets.count) polic\(targets.count == 1 ? "y" : "ies")?",
            message: "They stay in Jamf with their scope, payload and Self Service entry intact, but stop running on every Mac they currently reach. You can re-enable them from the Policies module.",
            actionTitle: "Disable \(targets.count)",
            role: nil,
            action: {
                onConfirmedAction(.disable, targets)
            }
        )
    }

    private func requestDelete() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        confirmation = ConfirmationData(
            title: "Delete \(targets.count) item\(targets.count == 1 ? "" : "s") from Jamf?",
            message: "This permanently removes \(selectionBreakdown) from this Jamf instance. It cannot be undone. Anything still receiving them will stop. If you are not certain, move them to a category instead.",
            actionTitle: "Delete \(targets.count)",
            role: .destructive,
            action: {
                onConfirmedAction(.delete, targets)
            }
        )
    }
}
