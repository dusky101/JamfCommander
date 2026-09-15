//
//  AddPackageView.swift
//  JamfCommander
//
//  Uploads a package an administrator supplies — a .pkg or .dmg that Installomator has no label for —
//  and creates the Self Service install policy for it, with the same category, scope, Self Service and
//  icon choices the Installomator flow offers.
//
//  Three steps run in order (`JamfAPIService+PackageUpload`): create the package record, upload the
//  file to it, create the policy. Each is reported on its own row afterwards, because the interesting
//  failures are the partial ones: a record with no file, or a package that arrived but has no policy.
//  Nothing is rolled back behind the administrator's back — the one exception is cancelling, where the
//  empty record this app created seconds earlier is cleared up rather than left as litter.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddPackageView: View {
    @ObservedObject var api: JamfAPIService

    /// Named in the confirmation, so it is never ambiguous which tenant is being written to.
    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    // Reference data
    @State private var categories: [Category] = []
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var computerGroups: [ComputerGroup] = []
    @State private var existingPackageNameKeys: Set<String> = []
    @State private var existingPolicyNameKeys: Set<String> = []
    @State private var nameCheckFailed = false
    @State private var jamfProVersion: String?
    @State private var isLoading = true
    @State private var loadFailed = false

    // The file
    @State private var selectedFileURL: URL?
    @State private var fileSize: Int64 = 0

    // Package details
    @State private var packageName = ""
    @State private var selectedCategoryID: Int?
    @State private var priority = 10
    @State private var rebootRequired = false
    @State private var info = ""
    @State private var notes = ""
    @State private var showOptionalDetails = false

    // Category creation
    @State private var isCreatingCategory = false
    @State private var newCategoryName = ""
    @State private var isSavingCategory = false
    @State private var categoryError: String?

    // Policy
    @State private var createsPolicy = true
    @State private var policyName = ""
    @State private var featureOnMainPage = false
    @State private var displayInSelfServiceCategory = true
    @State private var scopeConfig = DeploymentScopeConfig()

    // Icon
    @State private var selectedIcon: SelfServiceIcon?
    @State private var iconImage: NSImage?
    @State private var isUploadingIcon = false
    @State private var iconError: String?
    @State private var showIconPicker = false

    // The run
    @State private var stage: UploadStage = .idle
    @State private var runTask: Task<Void, Never>?
    @State private var results: [OperationResult] = []
    @State private var showResults = false
    @State private var confirmation: ConfirmationData?

    /// Where a run has got to. The upload carries its own fraction because it is the only step long
    /// enough to be worth a progress bar.
    private enum UploadStage: Equatable {
        case idle
        case creatingRecord
        case uploading(Double)
        case creatingPolicy
        case cleaningUp

        var isRunning: Bool { self != .idle }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                LoadingProgressView(message: "Loading Jamf data...")
            } else if loadFailed {
                loadErrorView
            } else if stage.isRunning {
                runningView
            } else if selectedFileURL == nil {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        fileCard
                        Divider()
                        packageDetailsSection
                        Divider()
                        policySection
                        if createsPolicy {
                            Divider()
                            selfServiceSection
                            Divider()
                            scopeSection
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                }

                Divider()
                footer
            }
        }
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showResults) {
            OperationResultView(
                title: "Upload Results",
                results: results,
                onDismiss: {
                    showResults = false
                    results = []
                }
            )
        }
        .sheet(isPresented: $showIconPicker) {
            SelfServiceIconPickerView(
                api: api,
                onPick: { icon in
                    showIconPicker = false
                    selectedIcon = icon
                    iconImage = nil
                    iconError = nil
                    if let iconID = icon.id { loadIconPreview(id: iconID) }
                },
                onCancel: { showIconPicker = false }
            )
        }
        .task { await loadReferenceData() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Package")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Upload a package Installomator has no label for, and create its install policy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let jamfProVersion {
                Text("Jamf Pro \(jamfProVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidGlassCapsule()
            }

            if selectedFileURL != nil && !stage.isRunning {
                Button("Start Again", role: .destructive) { clearFile() }
                    .buttonStyle(.bordered)
                    .help("Forgets the chosen file and its details. Nothing in Jamf is affected.")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let blockingIssue {
                Label(blockingIssue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }

            Spacer()

            Button(createsPolicy ? "Upload and Create Policy" : "Upload to Jamf", action: requestUpload)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canUpload)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            PackageDropZone { url in select(url) }
                .frame(maxWidth: 560)

            Text("The package is uploaded to Jamf's own distribution point. Your API client needs the Create, Read and Update Packages privileges.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var loadErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load the Jamf data for this page")
                .font(.headline)
            Text("Categories, computers and groups are needed before a package can be filed and scoped. Check your connection to Jamf and try again — nothing has been uploaded.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { Task { await loadReferenceData() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - The chosen file

    private var fileCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 28))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedFileURL?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileSize > 0 ? fileSize.formatted(.byteCount(style: .file)) : "Size unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Choose a Different File…") {
                clearFile()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .liquidGlass(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sections

    private var packageDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("1. Package Details")

            VStack(alignment: .leading, spacing: 4) {
                Text("Display name in Jamf")
                    .font(.caption)
                TextField("e.g. Oracle SQL Developer 24.3", text: $packageName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Package display name")

                if trimmedPackageName.isEmpty {
                    issueLabel("A package needs a display name.")
                } else if packageNameIsTaken {
                    issueLabel("Jamf already has a package called '\(trimmedPackageName)'. Package names must be unique — change it before uploading.")
                } else if nameCheckFailed {
                    Text("Could not check Jamf for existing package names. A name that is already taken will be reported when the record is created, before anything is uploaded.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LabeledContent("File name") {
                Text(fileNameForJamf)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
            .help("The name the file is stored under in Jamf. It comes from the file itself.")

            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.caption)
                categoryPicker
            }

            Stepper("Priority: \(priority)", value: $priority, in: 1...20)
                .help("The order Jamf installs packages in when a policy carries several. 10 is Jamf's default.")

            Toggle("Restart required after installing", isOn: $rebootRequired)
                .toggleStyle(.switch)

            DisclosureGroup(isExpanded: $showOptionalDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Info", text: $info, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                }
                .padding(.top, 6)
            } label: {
                Text("Info and notes (optional)")
                    .font(.caption)
            }

            Text("Everything else — fill user template, suppress Setup Assistant options, OS install — is created switched off and can be changed on the package in Jamf.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Category", selection: $selectedCategoryID) {
                    Text("Choose a category…").tag(Int?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Jamf category")

                if !isCreatingCategory {
                    Button {
                        isCreatingCategory = true
                    } label: {
                        Label("New Category", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isCreatingCategory {
                HStack(spacing: 8) {
                    TextField("New category name", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { createCategory() }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty || isSavingCategory)
                    Button {
                        isCreatingCategory = false
                        categoryError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel new category")
                }
            }

            if let categoryError {
                issueLabel(categoryError, tint: .orange)
            } else if selectedCategoryID == nil {
                issueLabel("Jamf files every package under a category, so one must be chosen.")
            }
        }
    }

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("2. Install Policy")

            Toggle("Create a Self Service install policy for this package", isOn: $createsPolicy)
                .toggleStyle(.switch)

            if createsPolicy {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Policy name")
                        .font(.caption)
                    TextField("e.g. Install Oracle SQL Developer", text: $policyName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Policy name")

                    if trimmedPolicyName.isEmpty {
                        issueLabel("A policy needs a name.")
                    } else if policyNameIsTaken {
                        issueLabel("Jamf already has a policy called '\(trimmedPolicyName)'. It will be rejected — the package itself would still upload.", tint: .orange)
                    }
                }

                Text("The policy is created enabled and offered in Self Service, exactly as the Installomator flow creates its policies.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The package will be uploaded and filed in Jamf, and nothing will install it. You can create a policy for it later in Jamf.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selfServiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("3. Self Service")

            Toggle("Feature on main page", isOn: $featureOnMainPage)
                .toggleStyle(.switch)

            Toggle("Display in '\(selectedCategoryName ?? "the selected category")'", isOn: $displayInSelfServiceCategory)
                .toggleStyle(.switch)
                .disabled(selectedCategoryID == nil)

            HStack(spacing: 12) {
                iconPreview

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedIcon?.id == nil ? "No icon" : (selectedIcon?.filename ?? "Existing Jamf icon"))
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(selectedIcon?.id == nil
                         ? "The policy will be created without a Self Service icon."
                         : "Attached to the policy once it is created.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isUploadingIcon { ProgressView().controlSize(.small) }
            }

            HStack(spacing: 8) {
                Button { pickAndUploadIcon() } label: {
                    Label("Upload Image…", systemImage: "square.and.arrow.up")
                }
                .disabled(isUploadingIcon)

                Button { showIconPicker = true } label: {
                    Label("Reuse Existing…", systemImage: "photo.on.rectangle")
                }
                .disabled(isUploadingIcon)

                if selectedIcon != nil {
                    Button {
                        selectedIcon = nil
                        iconImage = nil
                        iconError = nil
                    } label: {
                        Label("Remove", systemImage: "xmark.circle")
                    }
                    .disabled(isUploadingIcon)
                }

                Spacer()
            }

            if let iconError {
                issueLabel(iconError, tint: .orange)
            }
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("4. Scope")

            ScopeTargetPicker(
                scope: $scopeConfig,
                computers: computers,
                groups: computerGroups
            )

            if !scopeIsValid {
                issueLabel("Choose at least one target, or scope the policy to all computers.")
            }
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Text(stageTitle)
                    .font(.title3)
                    .fontWeight(.medium)

                if case .uploading(let fraction) = stage {
                    VStack(spacing: 6) {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(width: 360)
                        Text("\(Int(fraction * 100))% of \(fileSize > 0 ? fileSize.formatted(.byteCount(style: .file)) : "the package")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 360)
                }

                Text(stageDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Cancel", role: .destructive) {
                    runTask?.cancel()
                }
                .buttonStyle(.bordered)
                .disabled(stage == .cleaningUp)
            }
            .padding(30)
            .liquidGlassRect(cornerRadius: 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }

    private var stageTitle: String {
        switch stage {
        case .idle: return ""
        case .creatingRecord: return "Creating the package in Jamf…"
        case .uploading: return "Uploading \(selectedFileURL?.lastPathComponent ?? "the package")…"
        case .creatingPolicy: return "Creating the install policy…"
        case .cleaningUp: return "Cancelling…"
        }
    }

    private var stageDetail: String {
        switch stage {
        case .uploading:
            return "The package is prepared on disk and sent in one request. Leave this page open — cancelling stops the upload and removes the empty package from Jamf."
        case .cleaningUp:
            return "Removing the empty package record this upload created."
        default:
            return "Talking to \(instanceURL.isEmpty ? "Jamf" : instanceURL)."
        }
    }

    // MARK: - Small view helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
    }

    private func issueLabel(_ message: String, tint: Color = .red) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var iconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            if let iconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel(iconImage == nil ? "No Self Service icon chosen" : "Chosen Self Service icon")
    }

    // MARK: - Derived values

    private var trimmedPackageName: String {
        packageName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPolicyName: String {
        policyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name the file is stored under, sanitised once here so the record and the upload header can
    /// never disagree about it.
    private var fileNameForJamf: String {
        guard let selectedFileURL else { return "" }
        return JamfAPIService.sanitisedFileName(selectedFileURL.lastPathComponent)
    }

    private var selectedCategoryName: String? {
        categories.first { $0.id == selectedCategoryID }?.name
    }

    /// Blocks the upload: Jamf requires unique package names, and finding that out after sending a
    /// gigabyte would be an expensive way to learn it.
    private var packageNameIsTaken: Bool {
        guard !existingPackageNameKeys.isEmpty, !trimmedPackageName.isEmpty else { return false }
        return existingPackageNameKeys.contains(PolicyNameMatching.exactKey(trimmedPackageName))
    }

    /// Warns but does not block — a rejected policy still leaves the package in Jamf, so it costs far
    /// less than the upload and can be fixed afterwards.
    private var policyNameIsTaken: Bool {
        guard createsPolicy, !existingPolicyNameKeys.isEmpty, !trimmedPolicyName.isEmpty else { return false }
        return existingPolicyNameKeys.contains(PolicyNameMatching.exactKey(trimmedPolicyName))
    }

    private var scopeIsValid: Bool {
        guard createsPolicy else { return true }
        switch scopeConfig.scopeType {
        case .allComputers: return true
        case .specificComputers: return !scopeConfig.selectedComputerIDs.isEmpty
        case .smartComputerGroups, .staticComputerGroups: return !scopeConfig.selectedGroupIDs.isEmpty
        }
    }

    private var canUpload: Bool {
        selectedFileURL != nil
            && !trimmedPackageName.isEmpty
            && !packageNameIsTaken
            && selectedCategoryID != nil
            && scopeIsValid
            && (!createsPolicy || !trimmedPolicyName.isEmpty)
            && !isUploadingIcon
            && !stage.isRunning
    }

    /// The one thing standing in the way, for the footer. Ordered as the form reads.
    private var blockingIssue: String? {
        if trimmedPackageName.isEmpty { return "The package needs a display name." }
        if packageNameIsTaken { return "That package name is already used in Jamf." }
        if selectedCategoryID == nil { return "Choose a category." }
        if createsPolicy && trimmedPolicyName.isEmpty { return "The policy needs a name." }
        if !scopeIsValid { return "Choose what the policy deploys to." }
        if isUploadingIcon { return "Waiting for the icon to finish uploading." }
        return nil
    }

    // MARK: - File selection

    private func select(_ url: URL) {
        selectedFileURL = url
        fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0

        // A starting point rather than a guess dressed up as one: the file's own name without its
        // extension, which the administrator then edits.
        let suggestion = url.deletingPathExtension().lastPathComponent
        if packageName.isEmpty { packageName = suggestion }
        if policyName.isEmpty { policyName = "Install \(suggestion)" }
    }

    private func clearFile() {
        selectedFileURL = nil
        fileSize = 0
        packageName = ""
        policyName = ""
    }

    // MARK: - Confirmation

    /// Uploading writes to the live tenant and, with a policy, puts software in front of real Macs —
    /// so the administrator sees exactly what is about to happen first.
    private func requestUpload() {
        guard let selectedFileURL, let categoryName = selectedCategoryName else { return }

        let instance = instanceURL.isEmpty ? "your Jamf instance" : instanceURL
        let size = fileSize > 0 ? fileSize.formatted(.byteCount(style: .file)) : "unknown size"

        var message = "'\(selectedFileURL.lastPathComponent)' (\(size)) will be uploaded to \(instance) as the package '\(trimmedPackageName)' in '\(categoryName)'."

        if createsPolicy {
            message += "\n\nA Self Service policy named '\(trimmedPolicyName)' will be created, enabled, scoped to \(scopeConfig.summaryText.lowercased())."
            if policyNameIsTaken {
                message += " That policy name is already taken and will be rejected — the package will still upload."
            }
        } else {
            message += "\n\nNo policy will be created, so nothing will install it yet."
        }

        // Worth saying for anything sizeable: the multipart body is assembled on disk before it is
        // sent, so the Mac needs room for a second copy while the upload runs.
        if fileSize > 500_000_000 {
            message += "\n\nThe upload is prepared on disk first, so about \(size) of free space is needed while it runs."
        }

        confirmation = ConfirmationData(
            title: createsPolicy ? "Upload and create the policy?" : "Upload this package?",
            message: message,
            actionTitle: createsPolicy ? "Upload and Create" : "Upload",
            role: nil,
            action: { performUpload() }
        )
    }

    // MARK: - The run

    private func performUpload() {
        guard let fileURL = selectedFileURL,
              let categoryID = selectedCategoryID,
              let categoryName = selectedCategoryName else { return }

        let draft = JamfAPIService.JamfPackageDraft(
            packageName: trimmedPackageName,
            fileName: fileNameForJamf,
            categoryID: String(categoryID),
            priority: priority,
            info: info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : info,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            rebootRequired: rebootRequired
        )
        let policyNameForRun = trimmedPolicyName

        results = []
        stage = .creatingRecord

        runTask = Task {
            var steps: [OperationResult] = []

            // --- 1. The package record ---
            let packageID: String
            do {
                packageID = try await api.createPackageRecord(draft)
                steps.append(OperationResult(
                    itemName: "Package '\(draft.packageName)' created (ID \(packageID))",
                    success: true,
                    error: nil
                ))
            } catch {
                steps.append(OperationResult(
                    itemName: "Package '\(draft.packageName)'",
                    success: false,
                    error: Self.isCancellation(error)
                        ? "Cancelled before the package was created. If it does appear in Jamf, the request had already been accepted — remove it there."
                        : Self.reason(for: error)
                ))
                await finish(steps, uploaded: false)
                return
            }

            // --- 2. The file ---
            await MainActor.run { stage = .uploading(0) }
            do {
                try await api.uploadPackageFile(packageID: packageID, fileURL: fileURL) { fraction in
                    Task { @MainActor in
                        if case .uploading = stage { stage = .uploading(fraction) }
                    }
                }
                steps.append(OperationResult(
                    itemName: "Uploaded \(draft.fileName)",
                    success: true,
                    error: nil
                ))
            } catch {
                if Self.isCancellation(error) {
                    // The administrator stopped this deliberately, so the empty record the app made
                    // seconds ago is cleared up rather than left as litter. This is the only place
                    // anything is removed automatically, and only ever this one record.
                    await MainActor.run { stage = .cleaningUp }
                    // Detached on purpose: this task has just been cancelled, and every await in a
                    // cancelled task throws immediately — the clean-up would never reach Jamf.
                    let removed = await Task.detached { [api] in
                        do {
                            try await api.deletePackageRecord(id: packageID)
                            return true
                        } catch {
                            return false
                        }
                    }.value
                    steps.append(OperationResult(
                        itemName: "Upload of \(draft.fileName)",
                        success: false,
                        error: removed
                            ? "Cancelled. The empty package record was removed from Jamf."
                            : "Cancelled, but the empty package record (ID \(packageID)) could not be removed — delete it in Jamf."
                    ))
                } else {
                    steps.append(OperationResult(
                        itemName: "Upload of \(draft.fileName)",
                        success: false,
                        error: "\(Self.reason(for: error)) The package record (ID \(packageID)) exists in Jamf with no file attached — upload the file to it in Jamf, or delete it."
                    ))
                }
                await finish(steps, uploaded: false)
                return
            }

            // --- 3. The policy ---
            guard createsPolicy else {
                await finish(steps, uploaded: true)
                return
            }

            await MainActor.run { stage = .creatingPolicy }
            do {
                let policyID = try await api.createPackageInstallPolicy(
                    policyName: policyNameForRun,
                    packageID: packageID,
                    packageName: draft.packageName,
                    categoryName: categoryName,
                    featureOnMainPage: featureOnMainPage,
                    displayInSelfServiceCategory: displayInSelfServiceCategory,
                    scopeConfig: scopeConfig
                )
                steps.append(OperationResult(
                    itemName: "Policy '\(policyNameForRun)' created",
                    success: true,
                    error: nil
                ))
                if let iconID = selectedIcon?.id {
                    steps.append(await attachIcon(iconID: iconID, toPolicyID: policyID, policyName: policyNameForRun))
                }
            } catch {
                steps.append(OperationResult(
                    itemName: "Policy '\(policyNameForRun)'",
                    success: false,
                    error: "\(Self.reason(for: error)) The package itself uploaded successfully, so only the policy needs creating."
                ))
            }

            await finish(steps, uploaded: true)
        }
    }

    /// Attaches the chosen icon to the new policy, reporting an honest partial outcome — the policy
    /// exists either way, only the icon is missing.
    private func attachIcon(iconID: Int, toPolicyID policyID: Int?, policyName: String) async -> OperationResult {
        guard let policyID else {
            return OperationResult(
                itemName: "Self Service icon",
                success: false,
                error: "The policy was created, but Jamf did not return its id, so the icon could not be attached. Set it on the policy in Jamf."
            )
        }
        do {
            try await api.assignPolicyIcon(policyID: policyID, iconID: iconID)
            return OperationResult(itemName: "Self Service icon attached", success: true, error: nil)
        } catch {
            return OperationResult(
                itemName: "Self Service icon",
                success: false,
                error: "The policy was created (ID \(policyID)), but the icon could not be attached — this needs the 'Update Policies' privilege. Set it on the policy in Jamf."
            )
        }
    }

    /// Ends a run: show what actually happened, and only clear the form when the package really did
    /// reach Jamf, so a failure leaves everything in place to retry.
    @MainActor
    private func finish(_ steps: [OperationResult], uploaded: Bool) async {
        stage = .idle
        runTask = nil
        results = steps
        showResults = true

        if uploaded {
            clearFile()
            // The tenant now holds one more package, and possibly one more policy.
            await loadNameIndexes()
        }
    }

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

    /// The package and policy names already in Jamf, for the pre-flight checks. Advisory: if either
    /// read fails the page still works, and Jamf reports the clash itself.
    private func loadNameIndexes() async {
        let packageNames = try? await api.fetchPackageNames()
        let policyNames = try? await api.fetchPolicyNames()

        await MainActor.run {
            existingPackageNameKeys = Set((packageNames ?? []).map(PolicyNameMatching.exactKey))
            existingPolicyNameKeys = Set((policyNames ?? []).map(PolicyNameMatching.exactKey))
            nameCheckFailed = packageNames == nil
        }
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingCategory = true
        categoryError = nil

        Task {
            do {
                try await api.createCategory(name: name)
            } catch {
                // Never let a failed write look like a success: keep the field open and say so.
                await MainActor.run {
                    categoryError = "Could not create '\(name)' in Jamf. Check the name and your privileges, then try again."
                    isSavingCategory = false
                }
                return
            }

            let fresh = try? await api.fetchCategories()
            await MainActor.run {
                if let fresh {
                    categories = fresh.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    selectedCategoryID = fresh.first { $0.name == name }?.id ?? selectedCategoryID
                }
                isCreatingCategory = false
                newCategoryName = ""
                isSavingCategory = false
            }
        }
    }

    // MARK: - Icon

    /// Uploading only adds the image to Jamf's icon library — it changes no policy and reaches no
    /// device, so it isn't itself gated by a confirmation, exactly as in the deployment sheet.
    private func pickAndUploadIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .gif, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a Self Service icon (PNG or GIF recommended, ≈512×512)."
        panel.prompt = "Upload"

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        isUploadingIcon = true
        iconError = nil
        let filename = fileURL.lastPathComponent
        let mime = Self.mimeType(forPathExtension: fileURL.pathExtension)

        Task {
            do {
                let data = try Data(contentsOf: fileURL)
                let icon = try await api.uploadIcon(imageData: data, filename: filename, mimeType: mime)
                await MainActor.run {
                    isUploadingIcon = false
                    if let iconID = icon.id { IconImageCache.shared.store(id: iconID, data: data) }
                    selectedIcon = icon
                    iconImage = NSImage(data: data)
                }
            } catch {
                await MainActor.run {
                    isUploadingIcon = false
                    iconError = "Couldn't upload the icon. Check the image format (PNG, GIF or JPEG) and your Jamf permissions, then try again."
                }
            }
        }
    }

    private func loadIconPreview(id: Int) {
        Task {
            let image = await IconImageCache.shared.loadImage(id: id, using: api)
            await MainActor.run { iconImage = image }
        }
    }

    private static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Failures

    /// Whether a thrown error is the administrator's own cancellation rather than a fault.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// A reason the administrator can act on. The typed errors already carry actionable copy;
    /// anything else is reported plainly rather than leaking framework internals into the results.
    private static func reason(for error: Error) -> String {
        if let uploadError = error as? JamfAPIService.PackageUploadError {
            return uploadError.errorDescription ?? "Jamf rejected this step."
        }
        if let creationError = error as? JamfAPIService.PolicyCreationError {
            return creationError.errorDescription ?? "Jamf rejected this step."
        }
        if let urlError = error as? URLError {
            return "Could not reach Jamf: \(urlError.localizedDescription)"
        }
        return "This step failed for an unexpected reason. Check the package and policy in Jamf before retrying."
    }
}
