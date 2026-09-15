//
//  PackageEditSheet.swift
//  JamfCommander
//
//  Edits a deployed Installomator install policy in place: its name, enabled state, category, Self
//  Service presentation and icon, scope, and the Installomator label and overrides it runs with.
//
//  The sheet reads the policy's own payload from Jamf and prefills from it, so what is shown is what
//  Jamf currently holds — not what the dashboard inferred. Only the fields actually changed are
//  written (see `JamfAPIService+PackageEditing`), which is what makes it safe to retarget a label
//  without disturbing a scope somebody built by hand.
//
//  Editing the label is the repair for a **Missing** row: a policy created against a label that
//  Installomator has since withdrawn can be pointed at a current one instead of being deleted and
//  recreated.
//

import SwiftUI
import UniformTypeIdentifiers

struct PackageEditSheet: View {
    @ObservedObject var api: JamfAPIService

    /// The deployed row being edited.
    let item: InstallomatorItem
    /// The other deployed policies that run the same label — one per pinned version, typically.
    let siblings: [InstallomatorItem]
    /// Labels Installomator currently publishes, lowercased. Empty means the list could not be read,
    /// in which case no label is questioned.
    let upstreamLabels: Set<String>

    var onApply: ([JamfAPIService.InstallomatorPolicyEditJob]) -> Void
    var onCancel: () -> Void

    /// The script the administrator last deployed with — the final fallback when working out which
    /// script entry on this policy is the Installomator one.
    @AppStorage("installomatorScriptID") private var lastUsedScriptID = ""
    /// Named in the confirmation, so it is never ambiguous which tenant is being written to.
    @AppStorage("jamfInstanceURL") private var instanceURL = ""

    // Load state
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var original: Snapshot?
    @State private var scriptID: String?
    @State private var currentScopeDescription = ""
    @State private var hasExclusions = false

    // Reference data
    @State private var categories: [Category] = []
    @State private var existingPolicyNameKeys: Set<String> = []
    @State private var nameCheckFailed = false

    // Scope targets are only fetched if the administrator actually opts into changing the scope —
    // every edit would otherwise pull the whole computer inventory for nothing.
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var computerGroups: [ComputerGroup] = []
    @State private var isLoadingScopeTargets = false
    @State private var scopeTargetsFailed = false

    // Editable fields
    @State private var policyName = ""
    @State private var isEnabled = true
    @State private var selectedCategoryID: Int?
    @State private var featureOnMainPage = false
    @State private var displayInSelfServiceCategory = true
    @State private var label = ""
    @State private var overrides: [InstallomatorOverride] = []
    @State private var isChangingScope = false
    @State private var scopeConfig = DeploymentScopeConfig()
    @State private var scopeSearchText = ""
    @State private var applyToSiblings = false

    // Icon
    @State private var currentIconID: Int?
    @State private var currentIconImage: NSImage?
    @State private var replacementIcon: SelfServiceIcon?
    @State private var replacementIconImage: NSImage?
    @State private var isUploadingIcon = false
    @State private var iconError: String?
    @State private var showIconPicker = false

    @State private var confirmation: ConfirmationData?

    /// The policy's settings as Jamf held them when the sheet opened. Everything the sheet writes is
    /// decided by comparing against this, so an untouched field is never sent.
    private struct Snapshot {
        let policyName: String
        let isEnabled: Bool
        let categoryID: Int?
        let featureOnMainPage: Bool
        let displayInSelfServiceCategory: Bool
        let label: String
        let overrides: [InstallomatorOverride]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Reading the policy from Jamf…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed || original == nil {
                loadErrorView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        policySection
                        Divider()
                        categorySection
                        Divider()
                        selfServiceSection
                        Divider()
                        scopeSection
                        Divider()
                        installomatorSection
                        if !siblings.isEmpty {
                            Divider()
                            siblingsSection
                        }
                        Divider()
                        changeSummarySection
                    }
                    .padding()
                }
            }

            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 780, maxWidth: .infinity,
               minHeight: 600, idealHeight: 720, maxHeight: .infinity)
        .appBackground()
        .commanderConfirmation(data: $confirmation)
        .sheet(isPresented: $showIconPicker) {
            SelfServiceIconPickerView(
                api: api,
                onPick: { icon in
                    showIconPicker = false
                    replacementIcon = icon
                    replacementIconImage = nil
                    iconError = nil
                    if let iconID = icon.id { loadReplacementIconPreview(id: iconID) }
                },
                onCancel: { showIconPicker = false }
            )
        }
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Package")
                    .font(.headline)
                Text(item.policyName ?? item.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let policyID = item.policyID {
                Text("Policy ID \(policyID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !changeSummary.isEmpty {
                Text("\(changeSummary.count) \(changeSummary.count == 1 ? "change" : "changes")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Save Changes", action: requestSave)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSave)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var loadErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't read this policy from Jamf")
                .font(.headline)
            Text("The policy's own settings are needed before anything can be changed, so that an edit only writes what you actually change. Check your connection to Jamf and try again — nothing has been altered.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
                Button("Cancel", action: onCancel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Sections

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("1. Policy")

            TextField("Policy name", text: $policyName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Policy name")

            if trimmedName.isEmpty {
                issueLabel("A policy must have a name.")
            } else if nameIsTaken {
                issueLabel("Jamf already has a policy called '\(trimmedName)'. Policy names must be unique, so this would be rejected.")
            } else if nameCheckFailed {
                Text("Could not check Jamf for existing policy names. A name that is already taken will be reported after saving.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if renamesPolicy {
                Text("The Self Service display name is updated to match.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("Enabled in Jamf", isOn: $isEnabled)
                .toggleStyle(.switch)
                .help("A disabled policy stays in Jamf but never runs and is not offered in Self Service.")
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("2. Category")

            Picker("Category", selection: $selectedCategoryID) {
                Text("No category").tag(Int?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Jamf category")

            if categoryWouldBeCleared {
                issueLabel("This app can move a policy between categories but cannot remove it from one — choose a category, or leave the policy where it is.")
            }

            Text("The policy's category and its Self Service category are written together, so the admin console and Self Service stay in step.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                iconPreview(image: replacementIconImage ?? currentIconImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(iconStateTitle)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(iconStateDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                if replacementIcon != nil {
                    Button {
                        replacementIcon = nil
                        replacementIconImage = nil
                        iconError = nil
                    } label: {
                        Label("Keep Current Icon", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(isUploadingIcon)
                }

                Spacer()
            }

            if let iconError {
                issueLabel(iconError, tint: .orange)
            }

            Text("An icon can be replaced but not removed — the Classic API has no reliable way to clear one, so the policy keeps its current icon unless a new one is chosen.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("4. Scope")

            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundColor(.secondary)
                Text("Currently: \(currentScopeDescription)")
                    .font(.callout)
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassRect(cornerRadius: 8)

            Toggle("Replace the scope", isOn: $isChangingScope)
                .toggleStyle(.switch)
                .onChange(of: isChangingScope) {
                    if isChangingScope { Task { await loadScopeTargetsIfNeeded() } }
                }

            if isChangingScope {
                if isLoadingScopeTargets {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading computers and groups…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if scopeTargetsFailed {
                    issueLabel("Could not load computers and groups from Jamf, so the scope cannot be changed here. Everything else on this sheet still works.", tint: .orange)
                } else {
                    scopeEditor
                }

                Text(hasExclusions
                     ? "Replacing the scope overwrites the computers and groups this policy targets. Its exclusions and limitations are left exactly as they are."
                     : "Replacing the scope overwrites the computers and groups this policy targets.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Left untouched. Turn this on only to retarget the policy.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var scopeEditor: some View {
        Picker("Scope", selection: $scopeConfig.scopeType) {
            ForEach(DeploymentScopeType.allCases) { type in
                Label(type.rawValue, systemImage: type.icon).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: scopeConfig.scopeType) {
            scopeSearchText = ""
            scopeConfig.selectedGroupIDs.removeAll()
        }

        switch scopeConfig.scopeType {
        case .allComputers:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("The policy will be scoped to all managed computers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .cornerRadius(8)

        case .specificComputers:
            scopeComputerPicker

        case .smartComputerGroups, .staticComputerGroups:
            scopeGroupPicker
        }
    }

    private var installomatorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("5. Installomator")

            if scriptID == nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("The Installomator script entry on this policy could not be identified, so its label and overrides cannot be edited here. Everything else on this sheet still works. Check the policy's scripts in Jamf.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassRect(cornerRadius: 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label (script parameter 4)")
                        .font(.caption)
                    TextField("e.g. googlechrome", text: $label)
                        .textFieldStyle(.roundedBorder)
                        .fontDesign(.monospaced)
                        .accessibilityLabel("Installomator label")

                    if trimmedLabel.isEmpty {
                        issueLabel("Installomator needs a label to install anything.")
                    } else if labelIsUnknownUpstream {
                        issueLabel("'\(trimmedLabel)' is not in the current Installomator label list. Installomator will not recognise it and the policy will fail on every Mac it reaches — unless your Installomator script is a fork that defines it.", tint: .orange)
                    } else if labelChanged {
                        Text("This policy will install '\(trimmedLabel)' the next time it runs.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Overrides (script parameters 7–11)")
                        .font(.caption)

                    ForEach($overrides) { $override in
                        HStack(spacing: 6) {
                            Picker("", selection: $override.key) {
                                Text("Choose…").tag("")
                                ForEach(selectableOverrideKeys, id: \.self) { key in
                                    Text(key).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 145)
                            .accessibilityLabel("Override variable")

                            TextField("value", text: $override.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .accessibilityLabel("Override value")

                            Button {
                                overrides.removeAll { $0.id == override.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove this override")
                        }
                    }

                    Button {
                        overrides.append(InstallomatorOverride())
                    } label: {
                        Label("Add Override", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(overrides.count >= InstallomatorOverrides.maximumOverrides)
                    .help("A policy has room for five overrides (parameter7 to parameter11).")

                    if !overrideIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(overrideIssues, id: \.self) { issue in
                                issueLabel(issue.message)
                            }
                        }
                    }

                    Text("Overrides pin what Installomator fetches — most often appNewVersion and downloadURL. Clearing them all hands the choice back to the label, which then installs whatever the vendor is shipping. A pinned URL stops working the moment the vendor moves the file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var siblingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("6. Other policies using '\(item.label)'")

            Toggle("Also apply the shared settings to \(siblings.count) other \(siblings.count == 1 ? "policy" : "policies")", isOn: $applyToSiblings)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(siblings) { sibling in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(sibling.policyName ?? sibling.displayName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let pinnedVersion = sibling.pinnedVersion {
                            Text(pinnedVersion)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.purple)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassRect(cornerRadius: 8)

            Text("Shared settings are the category, Self Service options, icon, scope and enabled state. The policy name and the Installomator label and overrides are not applied — they are what tells these policies apart, and Jamf requires policy names to be unique.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var changeSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("What will be written")

            if changeSummary.isEmpty {
                Text("Nothing has been changed yet. Anything left alone here is left alone in Jamf — untouched sections are not sent at all.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(changeSummary, id: \.self) { change in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(change)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassRect(cornerRadius: 10)
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

    private func iconPreview(image: NSImage?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 48, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            if let image {
                Image(nsImage: image)
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
        .accessibilityLabel(replacementIcon == nil ? "Current Self Service icon" : "New Self Service icon")
    }

    private var scopeComputerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by name, serial, user or email...", text: $scopeSearchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search computers")
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            if !scopeConfig.selectedComputerIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer").foregroundColor(.blue)
                    Text("\(scopeConfig.selectedComputerIDs.count) selected")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { scopeConfig.selectedComputerIDs.removeAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                }
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filteredComputers.isEmpty {
                        Text(scopeSearchText.isEmpty ? "No computers found." : "No computers match “\(scopeSearchText)”.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(filteredComputers) { computer in
                        let isSelected = scopeConfig.selectedComputerIDs.contains(computer.id)
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray.opacity(0.4))
                            ComputerIdentityRow(computer: computer)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                scopeConfig.selectedComputerIDs.remove(computer.id)
                            } else {
                                scopeConfig.selectedComputerIDs.insert(computer.id)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint("Adds or removes this computer from the policy's scope")
                    }
                }
            }
            .frame(maxHeight: 150)
            .liquidGlassRect(cornerRadius: 6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        }
    }

    private var scopeGroupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search \(scopeConfig.scopeType.rawValue.lowercased())...", text: $scopeSearchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search groups")
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filteredGroups.isEmpty {
                        Text("No \(scopeConfig.scopeType.rawValue.lowercased()) found.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }

                    ForEach(filteredGroups) { group in
                        let isSelected = scopeConfig.selectedGroupIDs.contains(group.id)
                        Button {
                            if isSelected {
                                scopeConfig.selectedGroupIDs.remove(group.id)
                            } else {
                                scopeConfig.selectedGroupIDs.insert(group.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.4))
                                Image(systemName: group.groupTypeIcon)
                                    .foregroundColor(group.smartGroup == true ? .purple : .secondary)
                                Text(group.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(group.groupTypeLabel)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 150)
            .liquidGlassRect(cornerRadius: 6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        }
    }

    // MARK: - Derived values

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String {
        policyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCategoryName: String? {
        categories.first { $0.id == selectedCategoryID }?.name
    }

    /// "No category" is only ever a valid choice for a policy that already has none — it is there so
    /// such a policy shows its real state. Clearing an existing category would need a Classic shape
    /// this app has not proven, so it is refused rather than guessed at.
    private var categoryWouldBeCleared: Bool {
        guard let original else { return false }
        return original.categoryID != nil && selectedCategoryID == nil
    }

    private var renamesPolicy: Bool {
        guard let original else { return false }
        return !trimmedName.isEmpty && trimmedName != original.policyName
    }

    /// A rename onto a name Jamf already holds would be rejected, so it is caught here rather than
    /// collected as a failure afterwards. The policy's own current name is never a clash.
    private var nameIsTaken: Bool {
        guard renamesPolicy, !existingPolicyNameKeys.isEmpty else { return false }
        return existingPolicyNameKeys.contains(PolicyNameMatching.exactKey(trimmedName))
    }

    private var labelChanged: Bool {
        guard let original else { return false }
        return !trimmedLabel.isEmpty && trimmedLabel.caseInsensitiveCompare(original.label) != .orderedSame
    }

    /// Only questioned when the upstream list was actually read — an unreachable GitHub must not make
    /// every label look wrong.
    private var labelIsUnknownUpstream: Bool {
        guard !upstreamLabels.isEmpty, !trimmedLabel.isEmpty else { return false }
        return !upstreamLabels.contains(trimmedLabel.lowercased())
    }

    /// The allowed Installomator variables, plus any key already on the policy that this app does not
    /// support — so a hand-made override is visible and can be corrected rather than silently lost.
    private var selectableOverrideKeys: [String] {
        let present = overrides
            .map { $0.key.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !InstallomatorOverrides.allowedKeys.contains($0) }
        return InstallomatorOverrides.allowedKeys + Set(present).sorted()
    }

    private var overrideIssues: [InstallomatorOverrides.Issue] {
        // No version list is involved when editing one policy: a pinned version is just an
        // `appNewVersion` override like any other, so the rules that only apply to a multi-version
        // run are satisfied trivially by passing no versions.
        InstallomatorOverrides.issues(overrides: overrides, versions: [], nameTemplate: policyName)
    }

    private var resolvedOverrides: [String] {
        overrides
            .filter { !$0.isBlank }
            .prefix(InstallomatorOverrides.maximumOverrides)
            .map { $0.resolved(version: nil) }
    }

    private var overridesChanged: Bool {
        guard let original else { return false }
        let before = original.overrides.filter { !$0.isBlank }.map { $0.resolved(version: nil) }
        return before != resolvedOverrides
    }

    private var scopeIsValid: Bool {
        guard isChangingScope else { return true }
        if isLoadingScopeTargets || scopeTargetsFailed { return false }
        switch scopeConfig.scopeType {
        case .allComputers: return true
        case .specificComputers: return !scopeConfig.selectedComputerIDs.isEmpty
        case .smartComputerGroups, .staticComputerGroups: return !scopeConfig.selectedGroupIDs.isEmpty
        }
    }

    private var filteredComputers: [ComputerInventoryRecord] {
        computers.filter { $0.matches(scopeSearchText) }
    }

    private var filteredGroups: [ComputerGroup] {
        let groupsForScope = computerGroups.filter { group in
            switch scopeConfig.scopeType {
            case .smartComputerGroups: return group.smartGroup == true
            case .staticComputerGroups: return group.smartGroup != true
            case .allComputers, .specificComputers: return false
            }
        }
        if scopeSearchText.isEmpty { return groupsForScope }
        return groupsForScope.filter { $0.name.localizedCaseInsensitiveContains(scopeSearchText) }
    }

    /// Everything that differs from what Jamf held when the sheet opened, in the order it appears on
    /// the sheet. This drives the summary, the confirmation and whether saving is possible, so those
    /// three can never disagree about what is being written.
    private var changeSummary: [String] {
        guard let original else { return [] }
        var changes: [String] = []

        if renamesPolicy {
            changes.append("Rename to '\(trimmedName)' (in Jamf and in Self Service)")
        }
        if isEnabled != original.isEnabled {
            changes.append(isEnabled ? "Enable the policy" : "Disable the policy")
        }
        if selectedCategoryID != original.categoryID, let selectedCategoryName {
            changes.append("Move to category '\(selectedCategoryName)'")
        }
        if featureOnMainPage != original.featureOnMainPage {
            changes.append(featureOnMainPage ? "Feature on the Self Service main page" : "Stop featuring on the Self Service main page")
        }
        if displayInSelfServiceCategory != original.displayInSelfServiceCategory {
            changes.append(displayInSelfServiceCategory ? "Show in its Self Service category" : "Hide from its Self Service category")
        }
        if let iconID = replacementIcon?.id {
            changes.append("Replace the Self Service icon (icon ID \(iconID))")
        }
        if isChangingScope, scopeIsValid {
            changes.append("Replace the scope with \(scopeConfig.summaryText.lowercased())")
        }
        if labelChanged {
            changes.append("Install label '\(trimmedLabel)' instead of '\(original.label)'")
        }
        if overridesChanged {
            changes.append(resolvedOverrides.isEmpty
                           ? "Clear all Installomator overrides"
                           : "Set \(resolvedOverrides.count) Installomator \(resolvedOverrides.count == 1 ? "override" : "overrides")")
        }
        // Only when something shared actually changed: ticking the box on a rename-only edit writes
        // nothing to the siblings, and the summary must not say otherwise.
        if applyToSiblings, !siblings.isEmpty, !sharedEdit().isEmpty {
            changes.append("Apply the shared settings to \(siblings.count) other \(siblings.count == 1 ? "policy" : "policies")")
        }
        return changes
    }

    private var canSave: Bool {
        guard original != nil, !changeSummary.isEmpty else { return false }
        guard !trimmedName.isEmpty, !nameIsTaken, !categoryWouldBeCleared else { return false }
        guard scopeIsValid, !isUploadingIcon else { return false }
        if scriptID != nil {
            guard !trimmedLabel.isEmpty, overrideIssues.isEmpty else { return false }
        }
        return true
    }

    private var iconStateTitle: String {
        if let replacementIcon {
            if let filename = replacementIcon.filename, !filename.isEmpty { return filename }
            return "New Self Service icon"
        }
        return currentIconID == nil ? "No Self Service icon" : "Current Self Service icon"
    }

    private var iconStateDetail: String {
        if replacementIcon != nil {
            return applyToSiblings && !siblings.isEmpty
                ? "Will be applied to this policy and the other policies using this label."
                : "Will be applied when you save."
        }
        if let currentIconID {
            return "Icon ID \(currentIconID) — kept unless you choose a new one."
        }
        return "This policy has no icon in Self Service."
    }

    // MARK: - Edit construction

    /// The edit for the policy being edited: only what changed, so an untouched section is never sent.
    private func primaryEdit() -> JamfAPIService.InstallomatorPolicyEdit {
        var edit = sharedEdit()

        if renamesPolicy {
            edit.policyName = trimmedName
            // Matches how the app creates these policies, where the Self Service display name is the
            // policy name. Only written on a rename, so a display name deliberately set to something
            // else in Jamf survives an unrelated edit.
            edit.updateSelfServiceDisplayName = true
        }

        if let scriptID, labelChanged || overridesChanged {
            edit.installomator = JamfAPIService.InstallomatorScriptEdit(
                scriptID: scriptID,
                label: trimmedLabel,
                overrides: resolvedOverrides
            )
        }

        return edit
    }

    /// The parts of the edit that are safe to apply to every policy running this label: category,
    /// Self Service presentation, icon, scope and enabled state. Never the name (Jamf requires those
    /// to be unique) and never the label or overrides (they are what tells siblings apart).
    private func sharedEdit() -> JamfAPIService.InstallomatorPolicyEdit {
        var edit = JamfAPIService.InstallomatorPolicyEdit()
        guard let original else { return edit }

        if isEnabled != original.isEnabled {
            edit.enabled = isEnabled
        }

        // The Self Service listing carries both flags inside its category block, so a change to
        // either flag rewrites the category block too — otherwise Jamf would keep the old
        // "featured" state alongside the new one.
        let selfServiceChanged = selectedCategoryID != original.categoryID
            || featureOnMainPage != original.featureOnMainPage
            || displayInSelfServiceCategory != original.displayInSelfServiceCategory

        if selfServiceChanged {
            if let categoryID = selectedCategoryID, let categoryName = selectedCategoryName {
                edit.categoryID = categoryID
                edit.categoryName = categoryName
            }
            edit.featureOnMainPage = featureOnMainPage
            edit.displayInSelfServiceCategory = displayInSelfServiceCategory
        }

        if let iconID = replacementIcon?.id {
            edit.iconID = iconID
        }

        if isChangingScope, scopeIsValid {
            edit.scope = scopeConfig
        }

        return edit
    }

    private func jobs() -> [JamfAPIService.InstallomatorPolicyEditJob] {
        guard let policyID = item.policyID else { return [] }

        var jobs: [JamfAPIService.InstallomatorPolicyEditJob] = [
            JamfAPIService.InstallomatorPolicyEditJob(
                target: JamfAPIService.InstallomatorPolicyTarget(
                    policyID: policyID,
                    policyName: item.policyName ?? item.displayName,
                    label: item.label
                ),
                edit: primaryEdit()
            )
        ]

        if applyToSiblings {
            let shared = sharedEdit()
            guard !shared.isEmpty else { return jobs }
            for sibling in siblings {
                guard let siblingID = sibling.policyID else { continue }
                jobs.append(JamfAPIService.InstallomatorPolicyEditJob(
                    target: JamfAPIService.InstallomatorPolicyTarget(
                        policyID: siblingID,
                        policyName: sibling.policyName ?? sibling.displayName,
                        label: sibling.label
                    ),
                    edit: shared
                ))
            }
        }

        return jobs
    }

    // MARK: - Confirmation

    /// These are writes to production policies that real Macs install from, so the administrator sees
    /// the full list of changes, the policies affected and the tenant before anything is sent.
    private func requestSave() {
        let work = jobs()
        guard !work.isEmpty else { return }

        let instance = instanceURL.isEmpty ? "your Jamf instance" : instanceURL
        let policyCount = work.count
        let noun = policyCount == 1 ? "policy" : "policies"

        var message = "\(policyCount) \(noun) in \(instance) will be updated:\n\n"
        message += changeSummary.map { "• \($0)" }.joined(separator: "\n")
        message += "\n\nSelf Service and any Mac in scope will follow these settings the next time the policy runs."
        if labelChanged {
            message += " Macs that already have the old application keep it — changing the label changes what is installed next, not what is already there."
        }

        confirmation = ConfirmationData(
            title: "Save changes to \(policyCount) \(noun)?",
            message: message,
            actionTitle: "Save Changes",
            role: nil,
            action: { onApply(work) }
        )
    }

    // MARK: - Loading

    private func load() async {
        guard let policyID = item.policyID else {
            isLoading = false
            loadFailed = true
            return
        }

        isLoading = true
        loadFailed = false

        async let detailResult = api.fetchPolicyDetail(id: policyID)
        async let categoriesResult = api.fetchCategories()
        async let namesResult = api.fetchPolicyNames()

        // The duplicate-name check is advisory: if it can't run, the sheet still works and says so.
        let policyNames = try? await namesResult

        do {
            let (detail, fetchedCategories) = try await (detailResult, categoriesResult)
            let script = Self.installomatorScript(in: detail, label: item.label, lastUsedScriptID: lastUsedScriptID)
            let snapshot = Snapshot(
                policyName: detail.general.name,
                isEnabled: detail.general.enabled,
                categoryID: Self.usableCategoryID(detail.general.category),
                featureOnMainPage: detail.self_service?.feature_on_main_page ?? false,
                displayInSelfServiceCategory: detail.self_service?.self_service_categories?.first?.display_in ?? true,
                label: script?.parameter4?.trimmingCharacters(in: .whitespacesAndNewlines) ?? item.label,
                overrides: script.map(Self.overrides(in:)) ?? []
            )
            let iconID = detail.self_service?.self_service_icon?.id

            await MainActor.run {
                categories = fetchedCategories.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                if let policyNames {
                    // The policy's own name is not a clash with itself.
                    existingPolicyNameKeys = Set(policyNames.map(PolicyNameMatching.exactKey))
                        .subtracting([PolicyNameMatching.exactKey(snapshot.policyName)])
                    nameCheckFailed = false
                } else {
                    existingPolicyNameKeys = []
                    nameCheckFailed = true
                }

                original = snapshot
                scriptID = script?.id
                policyName = snapshot.policyName
                isEnabled = snapshot.isEnabled
                selectedCategoryID = snapshot.categoryID
                featureOnMainPage = snapshot.featureOnMainPage
                displayInSelfServiceCategory = snapshot.displayInSelfServiceCategory
                label = snapshot.label
                overrides = snapshot.overrides

                currentScopeDescription = Self.describe(scope: detail.scope)
                hasExclusions = Self.hasExclusions(detail.scope)
                currentIconID = iconID
                isLoading = false
            }

            if let iconID {
                let image = await IconImageCache.shared.loadImage(id: iconID, using: api)
                await MainActor.run { currentIconImage = image }
            }
        } catch {
            // No error body in the log — see root CLAUDE.md, invariant 4.
            print("[Installomator] Edit sheet could not read policy \(policyID)")
            await MainActor.run {
                isLoading = false
                loadFailed = true
            }
        }
    }

    /// Computers and groups are only needed once the administrator opts into replacing the scope, so
    /// opening the sheet doesn't pull the whole inventory for an edit that may only change a category.
    private func loadScopeTargetsIfNeeded() async {
        guard computers.isEmpty, computerGroups.isEmpty, !isLoadingScopeTargets else { return }

        isLoadingScopeTargets = true
        scopeTargetsFailed = false
        do {
            async let computersResult = api.fetchComputers()
            async let groupsResult = api.fetchComputerGroups()
            let (fetchedComputers, fetchedGroups) = try await (computersResult, groupsResult)
            await MainActor.run {
                computers = fetchedComputers
                computerGroups = fetchedGroups.sorted { lhs, rhs in
                    if lhs.smartGroup != rhs.smartGroup { return lhs.smartGroup == true }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                isLoadingScopeTargets = false
            }
        } catch {
            await MainActor.run {
                isLoadingScopeTargets = false
                scopeTargetsFailed = true
            }
        }
    }

    // MARK: - Icon

    /// Uploading only adds the image to Jamf's icon library — it changes no policy and reaches no
    /// device, so (as in the deployment sheet) it isn't itself gated by a confirmation. Attaching it
    /// happens on save, behind the confirmation.
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
                    if let iconID = icon.id {
                        IconImageCache.shared.store(id: iconID, data: data)
                    }
                    replacementIcon = icon
                    replacementIconImage = NSImage(data: data)
                }
            } catch {
                await MainActor.run {
                    isUploadingIcon = false
                    iconError = "Couldn't upload the icon. Check the image format (PNG, GIF or JPEG) and your Jamf permissions, then try again."
                }
            }
        }
    }

    private func loadReplacementIconPreview(id: Int) {
        Task {
            let image = await IconImageCache.shared.loadImage(id: id, using: api)
            await MainActor.run { replacementIconImage = image }
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

    // MARK: - Reading the policy

    /// The script entry on this policy that runs Installomator.
    ///
    /// Matched the same way the dashboard's scan matches, strongest signal first: the label already
    /// in parameter4, then a script named after Installomator, then the script this app last deployed
    /// with. Without a match the Installomator section stays read-only — rewriting the wrong script's
    /// parameters would break a policy rather than edit it.
    private static func installomatorScript(in detail: PolicyDetailXML, label: String, lastUsedScriptID: String) -> PolicyScript? {
        let scripts = detail.scripts ?? []

        if let byLabel = scripts.first(where: {
            ($0.parameter4 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(label) == .orderedSame
        }) {
            return byLabel
        }
        if let byName = scripts.first(where: { $0.name.localizedCaseInsensitiveContains("installomator") }) {
            return byName
        }
        if !lastUsedScriptID.isEmpty, let byID = scripts.first(where: { $0.id == lastUsedScriptID }) {
            return byID
        }
        return nil
    }

    /// Reads parameter7–parameter11 back into editable rows. A parameter that isn't `key=value` is
    /// skipped rather than shown as a half-parsed row.
    private static func overrides(in script: PolicyScript) -> [InstallomatorOverride] {
        [script.parameter7, script.parameter8, script.parameter9, script.parameter10, script.parameter11]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { parameter in
                guard let separator = parameter.firstIndex(of: "=") else { return nil }
                let key = String(parameter[parameter.startIndex..<separator])
                let value = String(parameter[parameter.index(after: separator)...])
                guard !key.isEmpty else { return nil }
                return InstallomatorOverride(key: key, value: value)
            }
    }

    /// Jamf reports "no category" as the reserved id -1, which must not be offered back as if it were
    /// a real category.
    private static func usableCategoryID(_ category: PolicyCategory?) -> Int? {
        guard let category, category.id > 0 else { return nil }
        return category.id
    }

    private static func describe(scope: PolicyScope) -> String {
        if scope.all_computers { return "all computers" }

        let computerCount = scope.computers?.count ?? 0
        let groupCount = scope.computer_groups?.count ?? 0

        var parts: [String] = []
        if computerCount > 0 { parts.append("\(computerCount) \(computerCount == 1 ? "computer" : "computers")") }
        if groupCount > 0 { parts.append("\(groupCount) \(groupCount == 1 ? "group" : "groups")") }

        guard !parts.isEmpty else { return "nothing — the policy has no targets, so it does not deploy" }
        return parts.formatted(.list(type: .and))
    }

    private static func hasExclusions(_ scope: PolicyScope) -> Bool {
        let computers = scope.exclusions?.computers?.count ?? 0
        let groups = scope.exclusions?.computer_groups?.count ?? 0
        return computers > 0 || groups > 0
    }
}
