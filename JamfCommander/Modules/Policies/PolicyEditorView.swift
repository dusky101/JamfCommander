//
//  PolicyEditorView.swift
//  JamfCommander
//
//  Form editor for a single policy's General settings: execution frequency and the six
//  standard event triggers plus an optional custom event trigger. Replaces hand-editing
//  the raw JSON for these fields.
//
//  Saving is a write to a live production Jamf tenant, so it is gated behind an explicit
//  CommanderConfirmation and reports the real outcome via OperationResultView — never a
//  faked success. All networking goes through JamfAPIService (`updatePolicyGeneral`).
//
//  Note on the "rolling" frequency selector: macOS has no wheel picker style
//  (`.wheel` is iOS/watchOS only), so this uses the native macOS popup `Picker` — the
//  platform-correct equivalent, matching Jamf's own admin console.
//

import SwiftUI

struct PolicyEditorView: View {
    @ObservedObject var api: JamfAPIService

    let policyId: Int
    let policyName: String
    let initialFrequency: PolicyFrequency
    let initialTriggers: PolicyTriggers
    /// Called after a successful save so the host inspector can refresh its read-only
    /// views (raw JSON, Self Service summary, scope).
    var onSaved: () async -> Void

    // Working copy the form mutates.
    @State private var frequency: PolicyFrequency
    @State private var triggers: PolicyTriggers
    // Last-saved baseline, used to detect unsaved changes and to revert.
    @State private var baselineFrequency: PolicyFrequency
    @State private var baselineTriggers: PolicyTriggers

    @State private var isSaving = false
    @State private var confirmation: ConfirmationData?
    @State private var results: [OperationResult] = []
    @State private var showResults = false

    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    init(api: JamfAPIService,
         policyId: Int,
         policyName: String,
         initialFrequency: PolicyFrequency,
         initialTriggers: PolicyTriggers,
         onSaved: @escaping () async -> Void) {
        self.api = api
        self.policyId = policyId
        self.policyName = policyName
        self.initialFrequency = initialFrequency
        self.initialTriggers = initialTriggers
        self.onSaved = onSaved
        _frequency = State(initialValue: initialFrequency)
        _triggers = State(initialValue: initialTriggers)
        _baselineFrequency = State(initialValue: initialFrequency)
        _baselineTriggers = State(initialValue: initialTriggers)
    }

    private var hasChanges: Bool {
        frequency != baselineFrequency || triggers != baselineTriggers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            frequencySection
            triggersSection
            customTriggerSection
            saveBar
        }
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showResults) {
            OperationResultView(
                title: "Policy Update",
                results: results,
                onDismiss: {
                    showResults = false
                    Task { await onSaved() }
                }
            )
        }
    }

    // MARK: - Execution Frequency

    private var frequencySection: some View {
        InfoSection(title: "Execution Frequency", icon: "clock.arrow.circlepath") {
            HStack {
                Text("How often this policy runs")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Execution Frequency", selection: $frequency) {
                    ForEach(PolicyFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
                .disabled(isSaving)
                .accessibilityLabel("Execution frequency")
            }
        }
    }

    // MARK: - Standard Triggers

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Triggers", systemImage: "bolt.fill")
                .font(.headline)
            Text("Tap to choose when this policy runs automatically.")
                .font(.caption)
                .foregroundColor(.secondary)

            GlassEffectContainer(spacing: 10) {
                FlowLayout(spacing: 10, alignment: .leading) {
                    triggerChip("Recurring Check-in", systemImage: "arrow.triangle.2.circlepath", isOn: $triggers.checkin)
                    triggerChip("Enrolment Complete", systemImage: "checkmark.seal", isOn: $triggers.enrollmentComplete)
                    triggerChip("Login", systemImage: "person.badge.key", isOn: $triggers.login)
                    triggerChip("Logout", systemImage: "rectangle.portrait.and.arrow.right", isOn: $triggers.logout)
                    triggerChip("Network State Change", systemImage: "network", isOn: $triggers.networkStateChanged)
                    triggerChip("Startup", systemImage: "power", isOn: $triggers.startup)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// An interactive Liquid Glass chip: a glass capsule that fills with the accent tint
    /// (and shows a checkmark) when its trigger is on.
    private func triggerChip(_ label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        let on = isOn.wrappedValue
        return Button {
            withAnimation(.snappy(duration: 0.25)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? "checkmark" : systemImage)
                Text(label)
            }
            .font(.callout)
            .fontWeight(on ? .semibold : .regular)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(.blue).interactive() : .regular.interactive(), in: .capsule)
        .disabled(isSaving)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Custom Trigger

    private var customTriggerSection: some View {
        InfoSection(title: "Custom Trigger", icon: "terminal") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Optional event name, e.g. install-acme", text: $triggers.customTrigger)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSaving)
                    .accessibilityLabel("Custom trigger event name")
                Text("Run from a Mac with sudo jamf policy -event <trigger>. Leave blank for none.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Save / Revert

    private var saveBar: some View {
        HStack(spacing: 10) {
            if isSaving {
                ProgressView().controlSize(.small)
                Text("Saving…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else if hasChanges {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.orange)
                Text("Unsaved changes")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Revert") {
                frequency = baselineFrequency
                triggers = baselineTriggers
            }
            .buttonStyle(.bordered)
            .disabled(!hasChanges || isSaving)

            Button("Save Changes") { requestSave() }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
        }
    }

    // MARK: - Logic

    private func requestSave() {
        let instance = instanceURL.isEmpty ? "your Jamf instance" : instanceURL

        var changes: [String] = []
        if frequency != baselineFrequency {
            changes.append("• Frequency → \(frequency.displayName)")
        }
        if triggers != baselineTriggers {
            let trimmed = triggers.trimmedCustomTrigger
            changes.append("• Triggers updated")
            if trimmed != baselineTriggers.trimmedCustomTrigger {
                changes.append("• Custom trigger → \(trimmed.isEmpty ? "(none)" : trimmed)")
            }
        }
        let summary = changes.isEmpty ? "• Update the policy's General settings." : changes.joined(separator: "\n")

        confirmation = ConfirmationData(
            title: "Confirm Policy Update",
            message: "You are about to update '\(policyName)' on \(instance).\n\n\(summary)\n\nThis affects live devices. Please confirm.",
            actionTitle: "Save Changes",
            role: .none,
            action: { performSave() }
        )
    }

    private func performSave() {
        isSaving = true

        // Snapshot the values we send so a slow network can't be raced by further edits,
        // and normalise the custom trigger (trim) so a whitespace-only value clears it.
        let snapshotFrequency = frequency
        var snapshotTriggers = triggers
        snapshotTriggers.customTrigger = triggers.trimmedCustomTrigger

        Task {
            let result: OperationResult
            do {
                try await api.updatePolicyGeneral(id: policyId, frequency: snapshotFrequency, triggers: snapshotTriggers)
                result = OperationResult(itemName: policyName, success: true, error: nil)
            } catch {
                result = OperationResult(itemName: policyName, success: false, error: "\(error)")
            }

            await MainActor.run {
                isSaving = false
                if result.success {
                    // Adopt the saved values as the new baseline and normalise the field.
                    frequency = snapshotFrequency
                    triggers = snapshotTriggers
                    baselineFrequency = snapshotFrequency
                    baselineTriggers = snapshotTriggers
                }
                results = [result]
                showResults = true
            }
        }
    }
}
