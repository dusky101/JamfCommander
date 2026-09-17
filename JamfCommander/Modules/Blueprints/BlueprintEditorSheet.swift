//
//  BlueprintEditorSheet.swift
//  JamfCommander
//
//  Creates a blueprint from supplied JSON, or updates an existing one.
//
//  The JSON is authored by the administrator — typed, pasted, or loaded from a .json file — and is
//  sent through `BlueprintPayload`, which validates the documented constraints and otherwise passes
//  the document through untouched. Nothing here rewrites a component's configuration.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Which job the sheet is doing. `Identifiable` so it can drive `.sheet(item:)`.
enum BlueprintEditorMode: Identifiable {
    case create
    case edit(Blueprint)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let blueprint): return "edit-\(blueprint.id)"
        }
    }

    var existing: Blueprint? {
        switch self {
        case .create: return nil
        case .edit(let blueprint): return blueprint
        }
    }
}

struct BlueprintEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: BlueprintEditorMode
    @ObservedObject var api: JamfAPIService

    /// Called after a successful write so the dashboard can refresh.
    var onSaved: () -> Void

    // MARK: State

    @State private var json = ""
    @State private var scopeChoice: ScopeChoice = .keepExisting
    @State private var selectedGroupIDs: Set<String> = []

    @State private var groups: [PlatformDeviceGroup] = []
    @State private var groupsState: GroupsState = .notLoaded

    @State private var summary = DraftSummary()
    @State private var isLoadingExisting = false
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var confirmation: ConfirmationData?

    enum ScopeChoice: String, CaseIterable, Identifiable {
        case keepExisting
        case chooseGroups
        case unscoped

        var id: String { rawValue }

        var label: String {
            switch self {
            case .keepExisting: return "Use the JSON"
            case .chooseGroups: return "Choose groups"
            case .unscoped: return "No scope"
            }
        }
    }

    enum GroupsState: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed(String)
    }

    /// What the current JSON declares, recomputed when it changes rather than inside `body`.
    struct DraftSummary {
        var name: String?
        var stepCount: Int?
        var groupIDsInJSON: [String] = []
    }

    private var isEditing: Bool { mode.existing != nil }

    private var title: String {
        if let existing = mode.existing {
            return "Edit “\(existing.name)”"
        }
        return "New Blueprint"
    }

    private var canSave: Bool {
        !isSaving
            && !isLoadingExisting
            && !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The scope that will actually be sent, translated for `BlueprintPayload`.
    private var scopeSelection: BlueprintScopeSelection {
        switch scopeChoice {
        case .keepExisting: return .keepExisting
        case .chooseGroups: return .groups(Array(selectedGroupIDs))
        case .unscoped: return .unscoped
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isLoadingExisting {
                loadingView
            } else if let loadError {
                loadFailureView(loadError)
            } else {
                HSplitView {
                    sidePane
                        .frame(width: 330)
                        .frame(maxHeight: .infinity)

                    editorPane
                        .frame(minWidth: 460, maxWidth: .infinity)
                }
            }

            Divider()

            footer
        }
        .frame(width: 980, height: 720)
        .liquidGlass(cornerRadius: 16)
        .commanderConfirmation(data: $confirmation)
        .task {
            await loadExistingIfNeeded()
        }
        .onChange(of: json) { _, newValue in
            refreshSummary(for: newValue)
        }
        .onChange(of: scopeChoice) { _, newValue in
            if newValue == .chooseGroups {
                Task { await loadGroupsIfNeeded() }
            }
        }
    }

    // MARK: Header & footer

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isEditing ? "square.and.pencil" : "plus.square.on.square")
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "EDIT BLUEPRINT" : "NEW BLUEPRINT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 16)

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                draftSummaryLabel
            }

            Spacer(minLength: 12)

            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            Button(isEditing ? "Save Changes" : "Create Blueprint") {
                prepareAndConfirm()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    @ViewBuilder
    private var draftSummaryLabel: some View {
        if json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Paste a blueprint definition, or choose a .json file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                if let name = summary.name {
                    Label(name, systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let stepCount = summary.stepCount {
                    Label(
                        stepCount == 1 ? "1 step" : "\(stepCount) steps",
                        systemImage: "list.number"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Label(scopeDescription, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var scopeDescription: String {
        switch scopeChoice {
        case .keepExisting:
            let count = summary.groupIDsInJSON.count
            if count == 0 { return "No scope in the JSON" }
            return count == 1 ? "1 group from the JSON" : "\(count) groups from the JSON"
        case .chooseGroups:
            let count = selectedGroupIDs.count
            if count == 0 { return "No groups selected" }
            return count == 1 ? "1 group selected" : "\(count) groups selected"
        case .unscoped:
            return "Unscoped"
        }
    }

    // MARK: Side pane

    private var sidePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourceSection
                scopeSection
            }
            .padding()
        }
    }

    private var sourceSection: some View {
        InfoSection(title: "Definition", icon: "doc.text") {
            Text("Type or paste the blueprint JSON on the right, or load it from a file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: chooseFile) {
                Label("Choose JSON File...", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)

            HStack(spacing: 8) {
                Button(action: pasteFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)

                Button(action: { json = "" }) {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || json.isEmpty)
            }

            if !isEditing {
                Text("Server-managed fields (id, created, updated, deploymentState) are removed before sending, so a definition copied from an existing blueprint can be pasted here as a starting point.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Only the keys present in this JSON are changed. Anything you leave out stays as it is on the server.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scopeSection: some View {
        InfoSection(title: "Scope", icon: "target") {
            Picker("Scope", selection: $scopeChoice) {
                ForEach(ScopeChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(isSaving)
            .accessibilityLabel("How to scope this blueprint")

            switch scopeChoice {
            case .keepExisting:
                Text("The `scope` object in your JSON is sent unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .chooseGroups:
                groupsArea

            case .unscoped:
                Label(
                    "Jamf documents at least one device group as required, so the server may refuse this. Whatever it answers is reported in full.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var groupsArea: some View {
        switch groupsState {
        case .notLoaded, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading device groups...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try Again") {
                    groupsState = .notLoaded
                    Task { await loadGroupsIfNeeded() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .loaded:
            BlueprintScopePicker(groups: groups, selection: $selectedGroupIDs)
        }
    }

    // MARK: Editor pane

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Blueprint JSON")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: formatJSON) {
                    Label("Format", systemImage: "text.alignleft")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(json.isEmpty || isSaving)
                .help("Re-indent the JSON")
            }
            .padding(10)
            .background(.ultraThinMaterial)

            Divider()

            TextEditor(text: $json)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .disabled(isSaving)
                .accessibilityLabel("Blueprint JSON")
        }
    }

    // MARK: Loading states

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Fetching the current definition...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadFailureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load The Blueprint", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await loadExistingIfNeeded() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func refreshSummary(for text: String) {
        summary = DraftSummary(
            name: BlueprintPayload.name(in: text),
            stepCount: BlueprintPayload.stepCount(in: text),
            groupIDsInJSON: BlueprintPayload.deviceGroupIDs(in: text)
        )
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Blueprint JSON File"
        panel.message = "Select a .json file containing a blueprint definition."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            // Pretty-printed when it parses; shown verbatim when it does not, so an invalid file
            // can still be read and corrected here rather than failing silently.
            json = BlueprintPayload.prettyPrinted(data)
            saveError = nil
        } catch {
            saveError = "Could not read that file: \(error.localizedDescription)"
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            saveError = "There is no text on the clipboard."
            return
        }
        json = text
        saveError = nil
    }

    private func formatJSON() {
        guard let data = json.data(using: .utf8) else { return }
        json = BlueprintPayload.prettyPrinted(data)
    }

    private func loadExistingIfNeeded() async {
        guard let existing = mode.existing, json.isEmpty else { return }

        isLoadingExisting = true
        loadError = nil

        do {
            json = try await api.fetchBlueprintJSON(id: existing.id)
            refreshSummary(for: json)
        } catch {
            loadError = error.localizedDescription
        }

        isLoadingExisting = false
    }

    private func loadGroupsIfNeeded() async {
        guard groupsState == .notLoaded else { return }
        groupsState = .loading

        do {
            groups = try await api.fetchPlatformDeviceGroups()
            // Pre-tick whatever the JSON already scopes to, so switching to this mode starts from
            // the blueprint's current scope rather than clearing it.
            if selectedGroupIDs.isEmpty {
                selectedGroupIDs = Set(summary.groupIDsInJSON)
            }
            groupsState = .loaded
        } catch {
            groupsState = .failed(error.localizedDescription)
        }
    }

    /// Validates locally, then puts the write behind an explicit confirmation naming exactly what
    /// will be sent. Nothing reaches the tenant until that is accepted.
    private func prepareAndConfirm() {
        saveError = nil

        let body: Data
        do {
            body = isEditing
                ? try BlueprintPayload.makeUpdateBody(json: json, scope: scopeSelection)
                : try BlueprintPayload.makeCreateBody(json: json, scope: scopeSelection)
        } catch {
            saveError = error.localizedDescription
            return
        }

        let name = summary.name ?? mode.existing?.name ?? "this blueprint"

        confirmation = ConfirmationData(
            title: isEditing ? "Save Changes?" : "Create Blueprint?",
            message: confirmationMessage(for: name),
            actionTitle: isEditing ? "Save Changes" : "Create",
            role: nil,
            action: { save(body: body) }
        )
    }

    private func confirmationMessage(for name: String) -> String {
        if let existing = mode.existing {
            return "“\(existing.name)” will be updated on the server, scoped as: \(scopeDescription.lowercased()). Only the keys present in your JSON are changed — anything omitted is left as it is."
        }
        return "A new blueprint “\(name)” will be created, scoped as: \(scopeDescription.lowercased()). Creating it does not deploy it — use Deploy once you are satisfied with it."
    }

    private func save(body: Data) {
        isSaving = true
        saveError = nil

        Task {
            do {
                if let existing = mode.existing {
                    try await api.updateBlueprint(id: existing.id, body: body)
                } else {
                    try await api.createBlueprint(body: body)
                }
                isSaving = false
                onSaved()
                dismiss()
            } catch {
                // Kept on screen rather than dismissing, so the JSON is not lost and can be fixed.
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
