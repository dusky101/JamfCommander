//
//  BulkSettingsSheet.swift
//  JamfCommander
//
//  Bulk in-place settings editor for multiple selected policies. Independently optional:
//  set an execution frequency for all, set a templated custom trigger for all
//  (`install-{appName}`, slugified, with a live per-row preview + per-row override), and
//  set a Self Service category for all (reuses `setPolicySelfServiceCategory`).
//
//  The sheet only *configures*; it returns the resolved per-row plan + config via
//  `onConfirm`. The host (ActionPanelView) shows a single confirmation and runs the
//  rate-limited batch (`bulkUpdatePolicySettings`), reporting real per-item results.
//

import SwiftUI

struct BulkSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var api: JamfAPIService

    let categories: [Category]
    let policies: [Policy]
    let onConfirm: ([BulkSettingsPlanItem], BulkSettingsConfig) -> Void

    @State private var applyFrequency = false
    @State private var chosenFrequency: PolicyFrequency = .oncePerComputer

    @State private var applyCustomTrigger = false
    @State private var triggerTemplate = "install-{appName}"

    @State private var applySSCategory = false
    @State private var selectedSSCategory: Category?

    @State private var applyRemoveScope = false

    @State private var rows: [Row] = []

    struct Row: Identifiable {
        let policyId: Int
        let originalName: String
        var customTrigger: String
        var isOverridden: Bool
        var id: Int { policyId }
    }

    /// At least one change selected, and if the SS toggle is on a category must be chosen.
    private var canApply: Bool {
        guard !policies.isEmpty else { return false }
        let somethingChosen = applyFrequency || applyCustomTrigger || applySSCategory || applyRemoveScope
        let ssValid = !applySSCategory || selectedSSCategory != nil
        return somethingChosen && ssValid
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    frequencySection
                    triggerSection
                    selfServiceSection
                    removeScopeSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 660)
        .appBackground()
        .onAppear(perform: seedRows)
        .onChange(of: triggerTemplate) { _, newTemplate in
            for index in rows.indices where !rows[index].isOverridden {
                rows[index].customTrigger = CloneTemplate.applyTriggerTemplate(newTemplate, policyName: rows[index].originalName)
            }
        }
    }

    // MARK: - Header / Footer

    private var header: some View {
        VStack(spacing: 6) {
            Text("Bulk Edit Settings")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Editing \(policies.count) polic\(policies.count == 1 ? "y" : "ies") in place")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Spacer()
            if applySSCategory && selectedSSCategory == nil {
                Text("Choose a Self Service category")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Button("Apply to \(policies.count) Polic\(policies.count == 1 ? "y" : "ies")") { confirm() }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!canApply)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Sections

    private var frequencySection: some View {
        card {
            sectionToggle("Set execution frequency", systemImage: "clock.arrow.circlepath", isOn: $applyFrequency)
            if applyFrequency {
                Picker("Frequency", selection: $chosenFrequency) {
                    ForEach(PolicyFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    private var triggerSection: some View {
        card {
            sectionToggle("Set custom trigger", systemImage: "terminal", isOn: $applyCustomTrigger)

            if applyCustomTrigger {
                Text("Use {appName} for the slugified app name (e.g. install-{appName}). Edit any row to override; leave a row blank to clear that policy's custom trigger.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. install-{appName}", text: $triggerTemplate)
                    .textFieldStyle(.roundedBorder)

                Divider()

                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        Text(rows[index].originalName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: 200, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                        TextField("No custom trigger", text: triggerBinding(index))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .fontDesign(.monospaced)
                        if rows[index].isOverridden {
                            Button { resetTrigger(index) } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Reset this trigger to the template")
                        }
                    }
                    if index < rows.count - 1 { Divider() }
                }
            }
        }
    }

    private var selfServiceSection: some View {
        card {
            sectionToggle("Set Self Service category", systemImage: "bag", isOn: $applySSCategory)

            if applySSCategory {
                Text("Sets each policy's Self Service category to the one chosen (display in Self Service).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Menu {
                    ForEach(categories) { category in
                        Button(category.name) { selectedSSCategory = category }
                    }
                } label: {
                    HStack {
                        Text(selectedSSCategory?.name ?? "Select Category…")
                            .foregroundColor(selectedSSCategory == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 260, alignment: .leading)
            }
        }
    }

    private var removeScopeSection: some View {
        card {
            sectionToggle("Remove scope", systemImage: "scope", isOn: $applyRemoveScope)
            if applyRemoveScope {
                Text("Unscopes every selected policy (all computers off, no targets, no exclusions). They will stop deploying until re-scoped.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    /// A section header row: leading label, the switch pinned to the trailing edge.
    private func sectionToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .liquidGlass()
    }

    // MARK: - Logic

    private func seedRows() {
        guard rows.isEmpty else { return }
        rows = policies.map { policy in
            Row(
                policyId: policy.id,
                originalName: policy.name,
                customTrigger: CloneTemplate.applyTriggerTemplate(triggerTemplate, policyName: policy.name),
                isOverridden: false
            )
        }
    }

    private func triggerBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { rows[index].customTrigger },
            set: { newValue in
                rows[index].customTrigger = newValue
                rows[index].isOverridden = true
            }
        )
    }

    private func resetTrigger(_ index: Int) {
        rows[index].customTrigger = CloneTemplate.applyTriggerTemplate(triggerTemplate, policyName: rows[index].originalName)
        rows[index].isOverridden = false
    }

    private func confirm() {
        guard canApply else { return }

        let items = rows.map { row in
            BulkSettingsPlanItem(policyId: row.policyId, policyName: row.originalName, customTrigger: row.customTrigger)
        }
        let config = BulkSettingsConfig(
            applyFrequency: applyFrequency ? chosenFrequency : nil,
            applyCustomTrigger: applyCustomTrigger,
            selfServiceCategoryID: applySSCategory ? selectedSSCategory?.id : nil,
            selfServiceCategoryName: applySSCategory ? selectedSSCategory?.name : nil,
            removeScope: applyRemoveScope
        )
        onConfirm(items, config)
        dismiss()
    }
}
