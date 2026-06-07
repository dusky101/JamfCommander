//
//  PolicySelfServiceEditorView.swift
//  JamfCommander
//
//  Form editor for a single policy's Self Service page settings: availability, display
//  name, button text, description, the "force users to view description" and "feature on
//  main page" flags, and the Self Service categories (each with display_in / feature_in).
//
//  Saving is a write to a live production Jamf tenant, so it is gated behind an explicit
//  CommanderConfirmation and reports the real outcome via OperationResultView. All
//  networking goes through JamfAPIService (`updatePolicySelfService`).
//
//  Icon upload / reuse is deliberately out of scope here (Phase 3.2 — it needs a
//  fileuploads multipart spike). The current icon is shown read-only and is preserved on
//  save: `updatePolicySelfService` re-sends the existing icon id when one is present.
//
//  Note: this reuses the global category *list* (`api.fetchCategories()`) rather than the
//  `CategorySelectionSheet`, because that sheet is themed for the move/deploy flow and
//  returns only a category name — Self Service needs the id plus display_in/feature_in.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PolicySelfServiceEditorView: View {
    @ObservedObject var api: JamfAPIService

    let policyId: Int
    let policyName: String
    let categories: [Category]
    let initialSettings: SelfServiceSettings
    /// Called after a successful save so the host inspector can refresh.
    var onSaved: () async -> Void

    @State private var settings: SelfServiceSettings
    @State private var baseline: SelfServiceSettings

    @State private var isSaving = false
    @State private var confirmation: ConfirmationData?
    @State private var results: [OperationResult] = []
    @State private var showResults = false

    // Icon state
    @State private var iconImage: NSImage?
    @State private var isUploadingIcon = false
    @State private var showIconPicker = false
    @State private var iconError: String?

    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    private var instanceLabel: String { instanceURL.isEmpty ? "your Jamf instance" : instanceURL }

    init(api: JamfAPIService,
         policyId: Int,
         policyName: String,
         categories: [Category],
         initialSettings: SelfServiceSettings,
         onSaved: @escaping () async -> Void) {
        self.api = api
        self.policyId = policyId
        self.policyName = policyName
        self.categories = categories
        self.initialSettings = initialSettings
        self.onSaved = onSaved
        _settings = State(initialValue: initialSettings)
        _baseline = State(initialValue: initialSettings)
    }

    private var hasChanges: Bool { settings != baseline }

    /// Categories not already attached to the policy's Self Service page.
    private var availableCategories: [Category] {
        categories
            .filter { candidate in !settings.categories.contains { $0.id == candidate.id } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            availabilitySection
            presentationSection
            descriptionSection
            optionsSection
            categoriesSection
            iconSection
            saveBar
        }
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showResults) {
            OperationResultView(
                title: "Self Service Update",
                results: results,
                onDismiss: {
                    showResults = false
                    Task { await onSaved() }
                }
            )
        }
        .sheet(isPresented: $showIconPicker) {
            SelfServiceIconPickerView(
                api: api,
                onPick: { icon in
                    iconError = nil
                    settings.icon = icon
                    showIconPicker = false
                },
                onCancel: { showIconPicker = false }
            )
        }
        .task(id: settings.icon?.id) { await loadIconPreview() }
    }

    // MARK: - Availability

    private var availabilitySection: some View {
        InfoSection(title: "Self Service", icon: "bag.fill") {
            Toggle(isOn: $settings.useForSelfService) {
                Label("Make available in Self Service", systemImage: "checkmark.circle")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .disabled(isSaving)
        }
    }

    // MARK: - Presentation

    private var presentationSection: some View {
        InfoSection(title: "Presentation", icon: "textformat") {
            labelledField("Display Name", text: $settings.displayName, placeholder: policyName)
            Divider()
            labelledField("Install Button", text: $settings.installButtonText, placeholder: "Install")
            Divider()
            labelledField("Reinstall Button", text: $settings.reinstallButtonText, placeholder: "Reinstall")
        }
    }

    private func labelledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)
                .accessibilityLabel(label)
        }
    }

    // MARK: - Description

    private var descriptionSection: some View {
        InfoSection(title: "Description", icon: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $settings.description)
                    .font(.callout)
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    .disabled(isSaving)
                    .accessibilityLabel("Self Service description")
                Toggle(isOn: $settings.forceUsersToViewDescription) {
                    Text("Force users to view description before running")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        InfoSection(title: "Options", icon: "star") {
            Toggle(isOn: $settings.featureOnMainPage) {
                Text("Feature on the Self Service main page")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .disabled(isSaving)
        }
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        InfoSection(title: "Self Service Categories", icon: "folder") {
            HStack {
                Menu {
                    ForEach(availableCategories) { category in
                        Button(category.name) { addCategory(category) }
                    }
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 200)
                .disabled(isSaving || availableCategories.isEmpty)
                Spacer()
            }

            if settings.categories.isEmpty {
                Text("Not listed under any Self Service category.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach($settings.categories) { $category in
                    Divider()
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").foregroundColor(.blue)
                        Text(category.name)
                            .font(.callout)
                        Spacer()
                        Toggle("Display", isOn: $category.displayIn)
                            .toggleStyle(.checkbox)
                            .help("List the policy under this Self Service category")
                        Toggle("Feature", isOn: $category.featureIn)
                            .toggleStyle(.checkbox)
                            .help("Feature the policy within this category")
                        Button(role: .destructive) {
                            removeCategory(category)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .help("Remove this Self Service category")
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func addCategory(_ category: Category) {
        guard !settings.categories.contains(where: { $0.id == category.id }) else { return }
        settings.categories.append(
            SelfServiceCategory(id: category.id, name: category.name, displayIn: true, featureIn: false)
        )
    }

    private func removeCategory(_ category: SelfServiceCategory) {
        settings.categories.removeAll { $0.id == category.id }
    }

    // MARK: - Icon (upload or reuse)

    private var iconSection: some View {
        InfoSection(title: "Icon", icon: "photo") {
            HStack(spacing: 12) {
                iconPreview
                VStack(alignment: .leading, spacing: 4) {
                    Text(iconSummary(settings.icon))
                        .font(.callout)
                        .fontWeight(.medium)
                    if let id = settings.icon?.id {
                        Text("Icon ID \(id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
                Spacer()
                if isUploadingIcon {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            HStack {
                Button { pickAndUploadImage() } label: {
                    Label("Upload Image…", systemImage: "square.and.arrow.up")
                }
                .disabled(isSaving || isUploadingIcon)

                Button {
                    showIconPicker = true
                } label: {
                    Label("Reuse Existing…", systemImage: "photo.on.rectangle")
                }
                .disabled(isSaving || isUploadingIcon)

                Spacer()
            }

            if let iconError {
                Text(iconError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Upload adds the image to Jamf's icon library and selects it; Reuse selects an existing icon by id. The icon is attached to the policy when you save the Self Service settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 64, height: 64)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel(iconImage == nil ? "No icon" : "Current Self Service icon")
    }

    private func iconSummary(_ icon: SelfServiceIcon?) -> String {
        guard let icon, icon.isAssigned else { return "No icon set" }
        if let filename = icon.filename, !filename.isEmpty { return filename }
        if let id = icon.id { return "Icon ID \(id)" }
        return "Assigned"
    }

    // MARK: - Icon preview / upload helpers

    private func loadIconPreview() async {
        guard let id = settings.icon?.id else {
            iconImage = nil
            return
        }
        iconImage = await IconImageCache.shared.loadImage(id: id, using: api)
    }

    private func pickAndUploadImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .gif, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Self Service icon (PNG or GIF recommended, ≈512×512)."
        panel.prompt = "Upload"

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        uploadIcon(from: fileURL)
    }

    /// Uploads the chosen image to Jamf's icon library and stages it as the policy's icon.
    /// The icon is only attached to the policy when the user saves the Self Service
    /// settings (the confirmed write), so the inert library upload isn't itself gated by a
    /// confirmation.
    private func uploadIcon(from fileURL: URL) {
        isUploadingIcon = true
        iconError = nil
        let filename = fileURL.lastPathComponent
        let mime = mimeType(forPathExtension: fileURL.pathExtension)

        Task {
            do {
                let data = try Data(contentsOf: fileURL)
                let icon = try await api.uploadIcon(imageData: data, filename: filename, mimeType: mime)
                await MainActor.run {
                    isUploadingIcon = false
                    if let iconId = icon.id {
                        // Cache the bytes we just uploaded so the preview is instant.
                        IconImageCache.shared.store(id: iconId, data: data)
                    }
                    settings.icon = icon   // staged; attached to the policy on Save
                }
            } catch {
                await MainActor.run {
                    isUploadingIcon = false
                    iconError = "Couldn't upload the icon. Check the image format (PNG or GIF) and your Jamf permissions, then try again."
                }
            }
        }
    }

    private func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
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

            Button("Revert") { settings = baseline }
                .buttonStyle(.bordered)
                .disabled(!hasChanges || isSaving)

            Button("Save Self Service") { requestSave() }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
        }
    }

    // MARK: - Logic

    private func requestSave() {
        confirmation = ConfirmationData(
            title: "Confirm Self Service Update",
            message: "You are about to update the Self Service page for '\(policyName)' on \(instanceLabel).\n\nThis changes what users see in Self Service. Please confirm.",
            actionTitle: "Save Self Service",
            role: .none,
            action: { performSave() }
        )
    }

    private func performSave() {
        isSaving = true

        // Snapshot and normalise (trim) the free-text fields so a slow network can't be
        // raced by further edits and whitespace-only values are tidied.
        var snapshot = settings
        snapshot.displayName = settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.installButtonText = settings.installButtonText.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.reinstallButtonText = settings.reinstallButtonText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let result: OperationResult
            do {
                try await api.updatePolicySelfService(id: policyId, settings: snapshot)
                result = OperationResult(itemName: policyName, success: true, error: nil)
            } catch {
                result = OperationResult(itemName: policyName, success: false, error: "\(error)")
            }

            await MainActor.run {
                isSaving = false
                if result.success {
                    settings = snapshot
                    baseline = snapshot
                }
                results = [result]
                showResults = true
            }
        }
    }
}
