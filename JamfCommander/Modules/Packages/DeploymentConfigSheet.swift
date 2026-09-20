//
//  DeploymentConfigSheet.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Scope Configuration Model

enum DeploymentScopeType: String, CaseIterable, Identifiable {
    case allComputers = "All Computers"
    case specificComputers = "Specific Computers"
    case smartComputerGroups = "Smart Groups"
    case staticComputerGroups = "Static Groups"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .allComputers: return "desktopcomputer"
        case .specificComputers: return "laptopcomputer"
        case .smartComputerGroups: return "gearshape.2.fill"
        case .staticComputerGroups: return "person.3.fill"
        }
    }
}

struct DeploymentScopeConfig {
    var scopeType: DeploymentScopeType = .allComputers
    var selectedComputerIDs: Set<String> = []   // Pro API uses String IDs
    var selectedGroupIDs: Set<Int> = []
    
    /// Generates the XML <scope> block for the Jamf Classic API
    func toScopeXML() -> String {
        switch scopeType {
        case .allComputers:
            return """
                <scope>
                    <all_computers>true</all_computers>
                </scope>
            """
        case .specificComputers:
            let computersXML = selectedComputerIDs.map {
                "<computer><id>\($0)</id></computer>"
            }.joined(separator: "\n                    ")
            return """
                <scope>
                    <all_computers>false</all_computers>
                    <computers>
                        \(computersXML)
                    </computers>
                </scope>
            """
        case .smartComputerGroups, .staticComputerGroups:
            let groupsXML = selectedGroupIDs.map {
                "<computer_group><id>\($0)</id></computer_group>"
            }.joined(separator: "\n                    ")
            return """
                <scope>
                    <all_computers>false</all_computers>
                    <computer_groups>
                        \(groupsXML)
                    </computer_groups>
                </scope>
            """
        }
    }
    
    /// Human-readable summary for the UI
    var summaryText: String {
        switch scopeType {
        case .allComputers:
            return "All Computers"
        case .specificComputers:
            return "\(selectedComputerIDs.count) computer(s)"
        case .smartComputerGroups:
            return "\(selectedGroupIDs.count) smart group(s)"
        case .staticComputerGroups:
            return "\(selectedGroupIDs.count) static group(s)"
        }
    }
}

// MARK: - Deployment Plan

/// Everything the sheet collects for one "Add to Jamf" run. Passed as a single value so the
/// callback doesn't grow another positional argument each time the flow gains an option.
struct InstallomatorDeploymentPlan {
    var categoryName: String
    var scriptID: String
    var featureOnMainPage: Bool
    var displayInSelfServiceCategory: Bool
    var scope: DeploymentScopeConfig
    var policyNameTemplate: String

    /// An icon already in Jamf's icon library, attached to each policy after it is created.
    /// `nil` — the default — leaves the policies without a Self Service icon, exactly as before.
    var iconID: Int?

    /// The policies to create **per selected label**. The default single unpinned variant reproduces
    /// today's behaviour exactly; several variants means one policy per pinned version.
    var variants: [InstallomatorPolicyVariant] = [.unpinned]
}

/// Carries a deployment into its window, and the finished plan back out.
///
/// The window is opened with `openWindow(id: DeploymentWindowID)`; this holds what it is
/// configuring and what it produced. `SettingsPresenter` and `HelpPresenter` have the same shape.
///
/// **It carries the service, where Settings did not.** Settings can own a `JamfAPIService` of its
/// own because the only Jamf call it makes reads credentials straight from `@AppStorage`. This
/// window cannot: it lists the tenant's categories, scripts, computers and groups, and then creates
/// policies, all of which need the authenticated session the app already holds. A fresh service
/// would have no token and every read would fail.
@MainActor
final class DeploymentPresenter: ObservableObject {
    static let shared = DeploymentPresenter()
    private init() {}

    /// The labels being deployed. Set immediately before the window is opened.
    @Published private(set) var pendingItems: [InstallomatorItem] = []

    /// The app's authenticated service — the same instance `ContentView` owns, not a copy.
    @Published private(set) var api: JamfAPIService?

    /// The plan the window produced. The module that opened it picks this up and does the work;
    /// the window itself creates nothing.
    @Published var completedPlan: InstallomatorDeploymentPlan?

    /// Hand the window a fresh deployment to configure.
    ///
    /// Deliberately clears everything first: a deployment window **starts clean each time** rather
    /// than coming back part-filled from last time (the maintainer's call, 20 September 2026).
    func begin(with items: [InstallomatorItem], api: JamfAPIService) {
        pendingItems = items
        self.api = api
        completedPlan = nil
    }
}

struct DeploymentConfigSheet: View {
    @ObservedObject var api: JamfAPIService

    /// The labels this run will create policies for, so their names can be resolved and checked
    /// against Jamf before anything is written.
    let pendingItems: [InstallomatorItem]

    var onConfirm: (InstallomatorDeploymentPlan) -> Void
    var onCancel: () -> Void

    // Data State
    @State private var categories: [Category] = []
    @State private var scripts: [ScriptRecord] = []
    @State private var computers: [ComputerInventoryRecord] = []
    @State private var computerGroups: [ComputerGroup] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    // Pre-flight duplicate-name check
    @State private var existingPolicyNameKeys: Set<String> = []
    @State private var nameCheckFailed = false

    // Confirmation before writing to the live tenant
    @State private var confirmation: ConfirmationData?

    /// Which step is showing. Starts at the beginning every time — the window does not come back
    /// part-filled, by decision (SHEET_NAVIGATION_HANDOVER.md, 20 September 2026).
    @State private var step: DeploymentStep = .category

    // Selection State
    @State private var selectedCategory: Category?
    @State private var selectedScriptID: String?
    @State private var searchText = ""
    
    // Policy Naming
    @State private var policyNameTemplate = DeploymentConfigSheet.defaultPolicyNameTemplate
    @State private var showNameReview = false

    // Version pinning (single-label runs only)
    @State private var isPinningVersions = false
    @State private var versionsText = ""
    @State private var overrides: [InstallomatorOverride] = [InstallomatorOverride()]
    
    // Self Service Options
    @State private var featureOnMainPage = false
    @State private var displayInSelfServiceCategory = true

    // Self Service Icon — uploaded (or picked) once per run; only the id reaches the batch
    @State private var selectedIcon: SelfServiceIcon?
    @State private var iconImage: NSImage?
    @State private var isUploadingIcon = false
    @State private var iconError: String?
    @State private var showIconPicker = false
    
    // Scope State
    @State private var scopeConfig = DeploymentScopeConfig()
    @State private var scopeSearchText = ""
    
    // Category Creation
    @State private var isCreatingCategory = false
    @State private var newCategoryName = ""
    @State private var isSavingCategory = false
    @State private var categoryError: String?
    
    var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Pre-flight Duplicate Check

    /// Whether version pinning is on offer. Overrides describe one app's downloads, so they only
    /// make sense for a run containing a single label — a pinned Python URL is meaningless for Firefox.
    private var supportsVersionPinning: Bool { pendingItems.count == 1 }

    /// The versions typed by the administrator, in the order given.
    private var pinnedVersions: [String] {
        guard supportsVersionPinning, isPinningVersions else { return [] }
        return InstallomatorOverrides.parseVersions(versionsText)
    }

    /// Anything that must be fixed before deploying.
    private var pinningIssues: [InstallomatorOverrides.Issue] {
        guard supportsVersionPinning, isPinningVersions else { return [] }
        return InstallomatorOverrides.issues(
            overrides: overrides,
            versions: pinnedVersions,
            nameTemplate: policyNameTemplate
        )
    }

    /// The policies this run will create for each label.
    private var plannedVariants: [InstallomatorPolicyVariant] {
        guard supportsVersionPinning, isPinningVersions else { return [.unpinned] }
        return InstallomatorOverrides.variants(overrides: overrides, versions: pinnedVersions)
    }

    /// The policy name for one label and one variant.
    private func resolvedName(for item: InstallomatorItem, variant: InstallomatorPolicyVariant) -> String {
        JamfAPIService.resolvePolicyName(
            template: policyNameTemplate,
            appName: item.displayName,
            version: variant.version
        )
    }

    /// One policy this run will create. Identified by position rather than by name, because two
    /// variants can briefly resolve to the same name while the template is being edited.
    private struct PlannedPolicy: Identifiable {
        let id: Int
        let item: InstallomatorItem
        let name: String
    }

    /// Every policy this run would create — one row per label per variant. Everything downstream
    /// (the duplicate check, the review list, the confirmation count) reads this, so pinning can
    /// never make those three disagree.
    private var plannedPolicies: [PlannedPolicy] {
        pendingItems
            .flatMap { item in plannedVariants.map { (item, $0) } }
            .enumerated()
            .map { index, unit in
                PlannedPolicy(id: index, item: unit.0, name: resolvedName(for: unit.0, variant: unit.1))
            }
    }

    /// The policy names this run would create, resolved from the current template.
    private var resolvedPolicyNames: [String] {
        plannedPolicies.map(\.name)
    }

    /// Labels whose app name is still one unbroken word, so the resulting policy name reads like the
    /// raw Installomator label ("Install Mysqlworkbenchce"). Worth a look before it is written.
    private var itemsWithAwkwardNames: [InstallomatorItem] {
        pendingItems.filter { InstallomatorLabelFormatter.looksUnsegmented($0.displayName) }
    }

    /// Names Jamf already holds. Creating these would be rejected with a duplicate-name conflict,
    /// so they are surfaced here rather than collected as failures after the batch has run.
    private var collidingPolicyNames: [String] {
        guard !existingPolicyNameKeys.isEmpty else { return [] }
        return resolvedPolicyNames.filter {
            existingPolicyNameKeys.contains(PolicyNameMatching.exactKey($0))
        }
    }

    /// "A, B and 3 more" — keeps a long list readable in a banner or dialog.
    private func summarise(_ names: [String], showing limit: Int = 3) -> String {
        guard names.count > limit else {
            return names.formatted(.list(type: .and))
        }
        let shown = names.prefix(limit).formatted(.list(type: .and))
        return "\(shown) and \(names.count - limit) more"
    }

    /// Searches on the same rule as the Computers dashboard — name, serial, assigned user or email —
    /// so an administrator can find a Mac by whoever it belongs to.
    var filteredComputers: [ComputerInventoryRecord] {
        computers.filter { $0.matches(scopeSearchText) }
    }
    
    var filteredGroups: [ComputerGroup] {
        let groupsForScope = computerGroups.filter { group in
            switch scopeConfig.scopeType {
            case .smartComputerGroups:
                return group.smartGroup == true
            case .staticComputerGroups:
                return group.smartGroup != true
            case .allComputers, .specificComputers:
                return false
            }
        }
        
        if scopeSearchText.isEmpty { return groupsForScope }
        return groupsForScope.filter {
            $0.name.localizedCaseInsensitiveContains(scopeSearchText)
        }
    }
    
    // MARK: - Steps

    /// The deployment, as the sequence it always was.
    ///
    /// The sheet numbered its own sections "1." to "6." in a single scroll, which was the right
    /// instinct and also the tell: a form that has to number itself so you can find your way back
    /// up it wants navigation. The numbers are the rail's job now.
    ///
    /// Clickable as well as sequential. The sheet was genuinely used both ways — accept every
    /// default and deploy, or go straight to scope — so Back and Next make the order plain while
    /// the rail keeps any step one click away.
    enum DeploymentStep: Int, CaseIterable, Identifiable {
        case category, script, naming, selfService, scope, pinning, review

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .category: "Category"
            case .script: "Installomator Script"
            case .naming: "Policy Names"
            case .selfService: "Self Service"
            case .scope: "Scope"
            case .pinning: "Version Pinning"
            case .review: "Review & Deploy"
            }
        }

        var icon: String {
            switch self {
            case .category: "folder"
            case .script: "applescript"
            case .naming: "textformat"
            case .selfService: "app.badge"
            case .scope: "target"
            case .pinning: "pin"
            case .review: "checkmark.seal"
            }
        }

        /// What this step is for, under its heading.
        var summary: String {
            switch self {
            case .category: "Where these policies are filed in Jamf, and where they appear in Self Service."
            case .script: "The Installomator script in your tenant that these policies will run."
            case .naming: "What each policy is called. Jamf allows duplicate names, so this is worth reading."
            case .selfService: "How the policies present themselves to the people using them."
            case .scope: "Which Macs the policies reach. Nothing installs anywhere you do not name here."
            case .pinning: "Advanced. Install a specific version rather than whatever Installomator finds today."
            case .review: "Everything these policies will do, before anything is sent to Jamf."
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading Jamf Data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                loadErrorView
            } else {
                stepper
            }
        }
        // A floor, not a target. The rail takes 230 of it, and the scope pickers and the pinning
        // editor are the two that need what is left.
        .frame(minWidth: 940, minHeight: 640)
        .appBackground()
        .commanderConfirmation(data: $confirmation)
        // A half-configured deployment does not survive being closed — that is the decision, and
        // this is the other half of it. See SHEET_NAVIGATION_HANDOVER.md, 20 September 2026.
        .confirmWindowClose(
            when: hasUnsavedChanges,
            title: "Discard this deployment?",
            message: "Nothing has been sent to Jamf. What you have set up here — the category, the naming, the scope and any pinned versions — is not kept, and the window starts empty next time.",
            discardTitle: "Discard",
            onDiscard: onCancel
        )
        .sheet(isPresented: $showIconPicker) {
            SelfServiceIconPickerView(
                api: api,
                onPick: { icon in
                    showIconPicker = false
                    selectedIcon = icon
                    iconError = nil
                    iconImage = nil
                    if let iconID = icon.id {
                        loadIconPreview(id: iconID)
                    }
                },
                onCancel: { showIconPicker = false }
            )
        }
        .onAppear(perform: loadData)
    }

    private var stepper: some View {
        NavigationSplitView {
            stepRail
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            stepDetail
        }
    }

    // MARK: - Rail

    private var stepRail: some View {
        VStack(spacing: 0) {
            // The sidebar runs the full height of the window, so the traffic lights float over its
            // first row — see SHEET_NAVIGATION_HANDOVER.md, which records this costing two attempts
            // on the Settings window. This reserves the strip they occupy.
            Color.clear
                .frame(height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(pendingItems.count == 1 ? "1 label" : "\(pendingItems.count) labels")
                    .font(.headline)
                if plannedPolicies.count != pendingItems.count {
                    Text("\(plannedPolicies.count) policies")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            List(DeploymentStep.allCases, selection: Binding(
                get: { step },
                set: { if let new = $0 { step = new } }
            )) { option in
                HStack(spacing: 10) {
                    // The number the section headings used to carry. It belongs here now: it says
                    // where you are in the sequence rather than repeating itself inside every page.
                    Text("\(option.rawValue + 1)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(width: 16)
                        .foregroundColor(.secondary)

                    Label(option.title, systemImage: option.icon)

                    Spacer()

                    if let issue = issue(for: option) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .help(issue)
                    } else if isComplete(option) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .tag(option)
                .help(option.summary)
            }
            .listStyle(.sidebar)
        }
    }

    /// Whether a step has been answered, for the tick in the rail.
    ///
    /// Only the steps that *must* be answered can be incomplete; the optional ones read as done
    /// because their defaults are a real answer. Deliberately derived from the same values the
    /// Deploy button is disabled on, so the rail and the button can never disagree.
    private func isComplete(_ option: DeploymentStep) -> Bool {
        switch option {
        case .category: selectedCategory != nil
        case .script: selectedScriptID != nil
        case .naming: !policyNameTemplate.isEmpty
        case .selfService: true
        case .scope: isScopeValid
        case .pinning: pinningIssues.isEmpty
        case .review: canDeploy
        }
    }

    /// Why a step is blocking deployment, if it is.
    private func issue(for option: DeploymentStep) -> String? {
        switch option {
        case .scope:
            isScopeValid ? nil : "Choose at least one target, or scope to all computers."
        case .pinning:
            pinningIssues.isEmpty ? nil : pinningIssues.map(\.message).joined(separator: "\n")
        default:
            nil
        }
    }

    // MARK: - Detail

    /// One step at a time, in a `ScrollView`.
    ///
    /// A `ScrollView` rather than a `VStack`, because a window's detail pane runs under the title
    /// bar and only a scroll view is inset for it — the Settings conversion drew its page heading
    /// behind the window title by getting this wrong.
    private var stepDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(step.summary)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                stepContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { footer }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .category: categoryStep
        case .script: scriptStep
        case .naming: namingStep
        case .selfService: selfServiceStep
        case .scope: scopeStep
        case .pinning: versionPinningSection
        case .review: reviewStep
        }
    }

    // MARK: - Footer

    /// Back, Next, and — on the last step only — Deploy.
    ///
    /// The sheet carried "Deploy Policies" in a footer that followed you down every section, so it
    /// was always one click away from a half-read form. It now lives where the maintainer asked for
    /// it: at the end, next to the summary of what it is about to do.
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button {
                    if let previous = DeploymentStep(rawValue: step.rawValue - 1) {
                        step = previous
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(step == .category)

                if step == .review {
                    Button("Deploy Policies", action: requestDeployment)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canDeploy)
                } else {
                    Button {
                        if let next = DeploymentStep(rawValue: step.rawValue + 1) {
                            step = next
                        }
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }

    /// Whether anything has been entered that closing the window would throw away.
    ///
    /// Compared against the values this window opens with, rather than a dirty flag set by each
    /// control: a flag has to be remembered every time a control is added, and the one that is
    /// forgotten is the one that silently loses somebody's work.
    ///
    /// Deliberately false for a window that was opened and not touched. A warning on every close is
    /// the one people learn to dismiss without reading, and this one stands in front of a form that
    /// creates policies on a live tenant.
    ///
    /// `overrides` is not checked directly: the editor that changes it only exists while
    /// `isPinningVersions` is on, so that flag already covers it.
    private var hasUnsavedChanges: Bool {
        selectedCategory != nil
            || selectedScriptID != nil
            || policyNameTemplate != Self.defaultPolicyNameTemplate
            || featureOnMainPage
            || !displayInSelfServiceCategory
            || selectedIcon != nil
            || scopeConfig.scopeType != .allComputers
            || !scopeConfig.selectedComputerIDs.isEmpty
            || !scopeConfig.selectedGroupIDs.isEmpty
            || isPinningVersions
            || !versionsText.isEmpty
    }

    /// The template the window opens with. A constant so `hasUnsavedChanges` and the `@State` that
    /// holds it cannot drift apart — the comparison is only as good as the two agreeing.
    static let defaultPolicyNameTemplate = "Install {appName}"

    /// Exactly the condition the sheet's Deploy button carried, named so the rail can use it too.
    private var canDeploy: Bool {
        selectedCategory != nil && selectedScriptID != nil && isScopeValid
            && !policyNameTemplate.isEmpty && pinningIssues.isEmpty
    }

    // MARK: - The steps themselves

    private var categoryStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedCategory) {
                ForEach(filteredCategories) { category in
                    HStack {
                        Image(systemName: "folder")
                        Text(category.name)
                        Spacer()
                        if selectedCategory?.id == category.id {
                            Image(systemName: "checkmark").foregroundColor(.blue)
                        }
                    }
                    .tag(category)
                }
            }
            .searchable(text: $searchText)
            .frame(height: 320)

            Divider()

            if isCreatingCategory {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Name", text: $newCategoryName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { createCategory() }
                            .disabled(newCategoryName.isEmpty || isSavingCategory)
                        Button(action: {
                            isCreatingCategory = false
                            categoryError = nil
                        }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel new category")
                    }

                    if let categoryError {
                        Label(categoryError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
            } else {
                Button(action: { isCreatingCategory = true }) {
                    Label("New Category", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .liquidGlassRect(cornerRadius: 12)
    }

    private var scriptStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            if scripts.isEmpty {
                Text("No scripts found in Jamf.")
                    .foregroundColor(.red)
            } else {
                Picker("", selection: $selectedScriptID) {
                    Text("Select a script...").tag(String?.none)
                    ForEach(scripts) { script in
                        Text(script.name).tag(Optional(script.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }

    private var namingStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. Install {appName}", text: $policyNameTemplate)
                .textFieldStyle(.roundedBorder)

            Text("Use **{appName}** for the application name, and **{version}** when pinning versions.")
                .font(.caption2)
                .foregroundColor(.secondary)

            if !policyNameTemplate.isEmpty, let first = plannedPolicies.first {
                HStack(spacing: 4) {
                    Text("Preview:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(first.name)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .italic()
                }
            }

            nameReview
        }
    }

    private var selfServiceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Feature on Main Page", isOn: $featureOnMainPage)
                .toggleStyle(.switch)

            Toggle("Display in '\(selectedCategory?.name ?? "Selected Category")'", isOn: $displayInSelfServiceCategory)
                .toggleStyle(.switch)
                .disabled(selectedCategory == nil)

            iconChooser
        }
    }

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Scope", selection: $scopeConfig.scopeType) {
                ForEach(DeploymentScopeType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon)
                        .tag(type)
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
                    Text("Policy will be scoped to all managed computers.")
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
    }

    // MARK: - Review

    /// What these policies will do, before anything is sent.
    ///
    /// The sheet had a summary box buried under section six and a pre-flight banner above the
    /// footer. Both belong here — the maintainer asked for a last step that shows what the policy
    /// will do and deploys it, and this is that step.
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            preflightBanner

            if let scriptID = selectedScriptID,
               let script = scripts.first(where: { $0.id == scriptID }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each policy will")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Run script").foregroundColor(.secondary)
                            Text(script.name).bold()
                        }
                        GridRow {
                            Text("Be filed under").foregroundColor(.secondary)
                            Text(selectedCategory?.name ?? "—").bold()
                        }
                        GridRow {
                            Text("Be named").foregroundColor(.secondary)
                            Text(policyNameTemplate).bold()
                        }
                        GridRow {
                            Text("In Self Service").foregroundColor(.secondary)
                            Text(featureOnMainPage ? "Featured on the main page" : "Standard listing")
                        }
                        GridRow {
                            Text("Icon").foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                if let iconImage {
                                    Image(nsImage: iconImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 18, height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Text(iconSummaryText).bold()
                            }
                        }
                        GridRow {
                            Text("Reach").foregroundColor(.secondary)
                            Text(scopeConfig.summaryText).bold()
                        }
                    }
                    .font(.callout)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassRect(cornerRadius: 12)
            }

            // The names themselves, because a template and a count are not the same as seeing what
            // will exist in Jamf afterwards.
            VStack(alignment: .leading, spacing: 8) {
                Text(plannedPolicies.count == 1
                     ? "1 policy will be created"
                     : "\(plannedPolicies.count) policies will be created")
                    .font(.headline)

                ForEach(Array(plannedPolicies.enumerated()), id: \.offset) { _, planned in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.secondary)
                        Text(planned.name)
                            .font(.callout)
                        Spacer()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassRect(cornerRadius: 12)
        }
    }

    // MARK: - Load Failure

    /// The categories, scripts, computers and groups are all needed to configure a deployment, so a
    /// failed load has to say so — it previously left an empty sheet with a permanently disabled
    /// Deploy button and no explanation.
    private var loadErrorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load the Jamf data for this sheet")
                .font(.headline)
            Text("Categories, scripts, computers and groups could not be fetched. Check your connection to Jamf and try again — nothing has been created.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Try Again") { loadData() }
                    .buttonStyle(.borderedProminent)
                Button("Cancel", action: onCancel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Version Pinning

    /// Optional per-label version pinning: one policy per version, each carrying its own
    /// Installomator argument overrides in parameter7–parameter11.
    ///
    /// The app cannot offer a list of *available* versions — labels discover those by scraping the
    /// vendor's site on the Mac at install time, and replicating that here would mean per-vendor
    /// scraping logic that silently goes stale. So the administrator supplies the versions and the
    /// URL pattern once, and the app expands, validates and previews.
    @ViewBuilder
    private var versionPinningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !supportsVersionPinning {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Available when a single label is selected — a pinned download URL describes one application, so it can't apply to a mixed batch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlassRect(cornerRadius: 10)
            } else {
                Picker("", selection: $isPinningVersions) {
                    Text("Let Installomator decide (recommended)").tag(false)
                    Text("Pin specific versions").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if isPinningVersions {
                    pinningEditor
                }
            }
        }
    }

    @ViewBuilder
    private var pinningEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Versions — one policy is created for each")
                    .font(.caption)
                TextField("e.g. 3.11.9, 3.12.7, 3.13.1", text: $versionsText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .accessibilityLabel("Versions to pin")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Installomator overrides — use {version} where the version appears")
                    .font(.caption)

                ForEach($overrides) { $override in
                    HStack(spacing: 6) {
                        Picker("", selection: $override.key) {
                            Text("Choose…").tag("")
                            ForEach(InstallomatorOverrides.allowedKeys, id: \.self) { key in
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
                            if overrides.isEmpty { overrides = [InstallomatorOverride()] }
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
            }

            pinningPreview

            if !pinningIssues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(pinningIssues, id: \.self) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Label("A pinned download URL stops working the moment the vendor moves or removes the file, and the policy will then fail on every Mac. Pinning an architecture-specific URL installs the wrong binary on the other architecture — for a genuine split, create one policy per architecture and scope each to an architecture-based smart group.", systemImage: "exclamationmark.shield")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassRect(cornerRadius: 10)
        // A thin amber edge marks this as the advanced, opt-in path without tinting the whole block.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    /// Exactly what will be written, per policy — no surprises at deploy time.
    @ViewBuilder
    private var pinningPreview: some View {
        if let item = pendingItems.first, !plannedVariants.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Will create \(plannedVariants.count) \(plannedVariants.count == 1 ? "policy" : "policies"):")
                    .font(.caption)
                    .fontWeight(.medium)

                ForEach(plannedVariants, id: \.self) { variant in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resolvedName(for: item, variant: variant))
                            .font(.caption)
                            .foregroundColor(.blue)
                        ForEach(Array(variant.overrides.enumerated()), id: \.offset) { index, parameter in
                            Text("parameter\(index + 7)  \(parameter)")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassRect(cornerRadius: 8)
        }
    }

    // MARK: - Policy Name Review

    /// Every policy name this run would create, so an awkward one is caught here rather than after
    /// it exists in Jamf. Installomator labels are lowercase and unpunctuated, and the app can only
    /// tidy the ones it recognises — so the names it is least sure about are marked for a look.
    @ViewBuilder
    private var nameReview: some View {
        if !pendingItems.isEmpty {
            DisclosureGroup(isExpanded: $showNameReview) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plannedPolicies) { planned in
                        let needsChecking = InstallomatorLabelFormatter.looksUnsegmented(planned.item.displayName)
                        HStack(spacing: 6) {
                            Image(systemName: needsChecking ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(needsChecking ? .orange : .green.opacity(0.7))
                            Text(planned.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(planned.item.label)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(needsChecking
                            ? "\(planned.name) — check this name"
                            : planned.name)
                    }
                }
                .padding(.top, 4)
                .frame(maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack(spacing: 6) {
                    Text("Review policy names (\(plannedPolicies.count))")
                        .font(.caption)
                    if !itemsWithAwkwardNames.isEmpty {
                        Text("\(itemsWithAwkwardNames.count) to check")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
            }
            .help("Names come from the Installomator label. Anything marked in amber is still one unbroken word — worth reading before it becomes a policy name.")
        }
    }

    // MARK: - Self Service Icon

    /// One icon for the whole run: no icon (the default), a local image uploaded to Jamf's icon
    /// library, or an existing Jamf icon reused by id. Whichever route is taken, the upload or
    /// lookup happens **once here** and only the resulting id is handed to the batch.
    private var iconChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                iconPreview

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedIcon?.id == nil ? "No icon" : (selectedIcon?.filename ?? "Existing Jamf icon"))
                        .font(.callout)
                        .fontWeight(.medium)
                    if let iconID = selectedIcon?.id {
                        Text("Icon ID \(iconID) — applied to every policy in this run")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Policies will be created without a Self Service icon.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isUploadingIcon {
                    ProgressView().controlSize(.small)
                }
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
                Label(iconError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One line describing the chosen icon, for the summary box.
    private var iconSummaryText: String {
        guard let iconID = selectedIcon?.id else { return "None" }
        if let filename = selectedIcon?.filename, !filename.isEmpty { return filename }
        return "Icon ID \(iconID)"
    }

    @ViewBuilder
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

    /// Uploading only adds the image to Jamf's icon library — it changes no policy and reaches no
    /// device, so (as in `PolicySelfServiceEditorView`) it isn't itself gated by a confirmation.
    /// Attaching it to real policies happens later, behind the deployment confirmation.
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
        let mime = mimeType(forPathExtension: fileURL.pathExtension)

        Task {
            do {
                let data = try Data(contentsOf: fileURL)
                let icon = try await api.uploadIcon(imageData: data, filename: filename, mimeType: mime)
                await MainActor.run {
                    isUploadingIcon = false
                    if let iconID = icon.id {
                        // Cache the bytes we just uploaded so the preview is instant.
                        IconImageCache.shared.store(id: iconID, data: data)
                    }
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

    private func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }

    /// Loads the preview for an icon reused from Jamf (the upload path already has the bytes).
    private func loadIconPreview(id: Int) {
        Task {
            let image = await IconImageCache.shared.loadImage(id: id, using: api)
            await MainActor.run { iconImage = image }
        }
    }

    // MARK: - Pre-flight Banner

    /// Warns about name clashes before anything is written, so the administrator can change the
    /// template or cancel and deselect — rather than collecting rejections after the fact.
    @ViewBuilder
    private var preflightBanner: some View {
        if !collidingPolicyNames.isEmpty {
            banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                text: "\(collidingPolicyNames.count) of \(pendingItems.count) policy names already exist in Jamf and will be rejected: \(summarise(collidingPolicyNames)). Change the name template, or cancel and deselect them."
            )
        } else if nameCheckFailed {
            banner(
                icon: "info.circle.fill",
                tint: .secondary,
                text: "Could not check Jamf for existing policy names. Any name that is already taken will be reported after the deployment."
            )
        }
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Confirmation

    /// Policy creation writes to the live tenant and installs software on real Macs, so the
    /// administrator confirms exactly what is about to happen first.
    private func requestDeployment() {
        guard let category = selectedCategory, let scriptID = selectedScriptID else { return }

        let count = plannedPolicies.count
        let noun = count == 1 ? "policy" : "policies"

        var message = "\(count) Self Service \(noun) will be created in Jamf under '\(category.name)', scoped to \(scopeConfig.summaryText.lowercased())."
        if let iconID = selectedIcon?.id {
            message += " Icon \(iconID) will be attached to each one."
        }
        if !pinnedVersions.isEmpty {
            message += " Versions pinned: \(pinnedVersions.joined(separator: ", "))."
        }
        if !collidingPolicyNames.isEmpty {
            message += "\n\n\(collidingPolicyNames.count) of these names already exist and will be rejected: \(summarise(collidingPolicyNames))."
        }

        let plan = InstallomatorDeploymentPlan(
            categoryName: category.name,
            scriptID: scriptID,
            featureOnMainPage: featureOnMainPage,
            displayInSelfServiceCategory: displayInSelfServiceCategory,
            scope: scopeConfig,
            policyNameTemplate: policyNameTemplate,
            iconID: selectedIcon?.id,
            variants: plannedVariants
        )

        confirmation = ConfirmationData(
            title: "Create \(count) \(noun)?",
            message: message,
            actionTitle: "Create \(noun.capitalized)",
            role: nil,
            action: { onConfirm(plan) }
        )
    }

    // MARK: - Scope Pickers
    
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
                    Image(systemName: "laptopcomputer")
                        .foregroundColor(.blue)
                    Text("\(scopeConfig.selectedComputerIDs.count) selected")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        scopeConfig.selectedComputerIDs.removeAll()
                    }
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
                        // The whole row is the toggle, so expose it as one selectable element
                        // rather than an unlabelled tick image beside some text.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint("Adds or removes this computer from the deployment scope")
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
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            
            if !scopeConfig.selectedGroupIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.blue)
                    Text("\(scopeConfig.selectedGroupIDs.count) selected")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        scopeConfig.selectedGroupIDs.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if filteredGroups.isEmpty {
                        Text(scopeSearchText.isEmpty ? "No \(scopeConfig.scopeType.rawValue.lowercased()) found." : "No matching groups found.")
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
                                if let memberCount = group.memberCount {
                                    Text("\(memberCount)")
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
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
    
    // MARK: - Validation
    
    private var isScopeValid: Bool {
        switch scopeConfig.scopeType {
        case .allComputers:
            return true
        case .specificComputers:
            return !scopeConfig.selectedComputerIDs.isEmpty
        case .smartComputerGroups, .staticComputerGroups:
            return !scopeConfig.selectedGroupIDs.isEmpty
        }
    }
    
    // MARK: - Logic
    
    func loadData() {
        isLoading = true
        loadFailed = false
        Task {
            // Tiny delay to allow sheet animation to finish before heavy lifting
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            
            do {
                async let fetchedCats = api.fetchCategories()
                async let fetchedScripts = api.fetchScripts()
                async let fetchedComputers = api.fetchComputers()
                async let fetchedGroups = api.fetchComputerGroups()
                async let fetchedPolicyNames = api.fetchPolicyNames()

                // The duplicate-name check is advisory: if it can't run, the sheet still works and
                // says so in the banner rather than blocking the deployment.
                let policyNames = try? await fetchedPolicyNames

                let (cats, scrts, comps, grps) = try await (fetchedCats, fetchedScripts, fetchedComputers, fetchedGroups)

                await MainActor.run {
                    if let policyNames {
                        self.existingPolicyNameKeys = Set(policyNames.map(PolicyNameMatching.exactKey))
                        self.nameCheckFailed = false
                    } else {
                        self.existingPolicyNameKeys = []
                        self.nameCheckFailed = true
                    }

                    self.categories = cats.sorted { $0.name < $1.name }
                    self.scripts = scrts.sorted { $0.name < $1.name }
                    self.computers = comps
                    self.computerGroups = grps.sorted { lhs, rhs in
                        if lhs.smartGroup != rhs.smartGroup {
                            return lhs.smartGroup == true
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    
                    if let match = scrts.first(where: { $0.name.localizedCaseInsensitiveContains("Installomator") }) {
                        self.selectedScriptID = match.id
                    }
                    
                    self.isLoading = false
                }
            } catch {
                // Deliberately no error body in the log — see root CLAUDE.md, invariant 4. The sheet
                // shows the administrator an actionable message instead.
                print("[Installomator] Deployment sheet data load failed")
                await MainActor.run {
                    self.isLoading = false
                    self.loadFailed = true
                }
            }
        }
    }
    
    func createCategory() {
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
                    self.categoryError = "Could not create '\(name)' in Jamf. Check the name and your privileges, then try again."
                    self.isSavingCategory = false
                }
                return
            }

            let freshCats = try? await api.fetchCategories()
            await MainActor.run {
                if let fresh = freshCats {
                    self.categories = fresh.sorted { $0.name < $1.name }
                    if let new = fresh.first(where: { $0.name == name }) {
                        self.selectedCategory = new
                    }
                }
                self.isCreatingCategory = false
                self.newCategoryName = ""
                self.categoryError = nil
                self.isSavingCategory = false
            }
        }
    }
}
