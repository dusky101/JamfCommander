//
//  BulkCloneSheet.swift
//  JamfCommander
//
//  Multi-select bulk clone for policies. Configures a target category, a naming template
//  (prefix + original name + suffix), a custom-trigger template (`install-{appName}`,
//  slugified, with a live per-row preview and per-row override), the existing safety
//  strips, and an optional execution frequency to apply to every clone.
//
//  This sheet only *configures* the clone; it returns the resolved per-row plan and the
//  shared config via `onConfirm`. The host (ActionPanelView) shows a single confirmation
//  and runs the rate-limited batch (`JamfAPIService.bulkClonePolicies`), reporting real
//  per-item results. Clones are always created disabled (see `clonePolicy`).
//

import SwiftUI

struct BulkCloneSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var api: JamfAPIService

    let categories: [Category]
    let policies: [Policy]
    let onConfirm: ([BulkClonePlanItem], BulkCloneConfig) -> Void

    @State private var selectedCategory: Category?
    @State private var prefix = "Copy of "
    @State private var suffix = ""
    @State private var triggerTemplate = "install-{appName}"

    @State private var applyFrequencyEnabled = false
    @State private var chosenFrequency: PolicyFrequency = .oncePerComputer

    // Safety strips (match CloneConfigSheet defaults).
    @State private var stripScope = true
    @State private var stripTriggers = true
    @State private var stripFrequency = true
    @State private var disableSelfService = true

    @State private var rows: [CloneRow] = []

    struct CloneRow: Identifiable {
        let policyId: Int
        let originalName: String
        var customTrigger: String
        var isOverridden: Bool
        var id: Int { policyId }
    }

    private var hasName: Bool {
        !prefix.trimmingCharacters(in: .whitespaces).isEmpty || !suffix.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canClone: Bool {
        selectedCategory != nil && hasName && !policies.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    categorySection
                    namingSection
                    triggerSection
                    applySettingsSection
                    stripSection
                    previewSection
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 680)
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
            Text("Bulk Clone")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Cloning \(policies.count) polic\(policies.count == 1 ? "y" : "ies") — clones are created disabled")
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
            if !hasName {
                Text("Add a prefix or suffix so clones get unique names")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Button("Clone \(policies.count) Polic\(policies.count == 1 ? "y" : "ies")") { confirm() }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!canClone)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Sections

    private var categorySection: some View {
        card {
            Label("Target Category", systemImage: "folder")
                .font(.headline)
            Menu {
                ForEach(categories) { category in
                    Button(category.name) { selectedCategory = category }
                }
            } label: {
                HStack {
                    Text(selectedCategory?.name ?? "Select Category…")
                        .foregroundColor(selectedCategory == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var namingSection: some View {
        card {
            Label("Naming", systemImage: "textformat")
                .font(.headline)
            Text("New name = prefix + original name + suffix.")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Text("Prefix").font(.callout).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                TextField("e.g. “Copy of ”", text: $prefix).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Suffix").font(.callout).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                TextField("e.g. “ (Test)”", text: $suffix).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var triggerSection: some View {
        card {
            Label("Custom Trigger Template", systemImage: "terminal")
                .font(.headline)
            Text("Use {appName} for the slugified app name (e.g. install-{appName}). Edit any row below to override; leave a row blank for no trigger.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("e.g. install-{appName}", text: $triggerTemplate)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var applySettingsSection: some View {
        card {
            Label("Apply to Clones", systemImage: "slider.horizontal.3")
                .font(.headline)
            Toggle(isOn: $applyFrequencyEnabled) {
                Text("Set execution frequency for all clones").font(.callout)
            }
            .toggleStyle(.switch)
            if applyFrequencyEnabled {
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

    private var stripSection: some View {
        card {
            Label("Safety", systemImage: "shield")
                .font(.headline)
            Text("Choose what to strip from each clone. Clones are always created disabled.")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle("Remove scope (unscoped — not deployed)", isOn: $stripScope).toggleStyle(.checkbox)
            Toggle("Remove standard triggers (check-in, login, …)", isOn: $stripTriggers).toggleStyle(.checkbox)
            Toggle("Reset frequency to “Once per computer”", isOn: $stripFrequency).toggleStyle(.checkbox)
            Toggle("Disable Self Service", isOn: $disableSelfService).toggleStyle(.checkbox)
        }
    }

    private var previewSection: some View {
        card {
            Label("Preview (\(policies.count))", systemImage: "list.bullet.rectangle")
                .font(.headline)
            ForEach(rows.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(rows[index].originalName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                        Text(CloneTemplate.newName(prefix: prefix, original: rows[index].originalName, suffix: suffix))
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "terminal").font(.caption2).foregroundColor(.secondary)
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
                }
                .padding(.vertical, 6)
                if index < rows.count - 1 { Divider() }
            }
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
            CloneRow(
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
        guard let category = selectedCategory, canClone else { return }

        let items = rows.map { row in
            BulkClonePlanItem(
                policyId: row.policyId,
                originalName: row.originalName,
                newName: CloneTemplate.newName(prefix: prefix, original: row.originalName, suffix: suffix),
                customTrigger: row.customTrigger
            )
        }
        let config = BulkCloneConfig(
            targetCategoryID: category.id,
            targetCategoryName: category.name,
            stripScope: stripScope,
            stripTriggers: stripTriggers,
            stripFrequency: stripFrequency,
            disableSelfService: disableSelfService,
            applyFrequency: applyFrequencyEnabled ? chosenFrequency : nil
        )
        onConfirm(items, config)
        dismiss()
    }
}
