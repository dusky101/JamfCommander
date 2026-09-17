//
//  BlueprintsDashboardView.swift
//  JamfCommander
//
//  Lists the blueprints in the platform environment and runs the per-item lifecycle actions.
//
//  This module talks to the Platform API Gateway, not the Jamf Pro instance, so being signed in
//  to Jamf Pro is neither required nor sufficient. When the gateway credentials are missing the
//  view says so and offers Settings rather than reporting a failed request.
//

import SwiftUI

struct BlueprintsDashboardView: View {
    @ObservedObject var api: JamfAPIService

    /// Owned by `ContentView`; set to open the Settings sheet from the not-configured state.
    @Binding var showConfigSheet: Bool

    @State private var blueprints: [Blueprint] = []
    @State private var searchText = ""
    @State private var loadState: LoadState = .loading
    @State private var inspected: Blueprint?
    @State private var editor: BlueprintEditorMode?
    @State private var confirmation: ConfirmationData?
    @State private var outcome: OperationOutcome?
    @State private var isWorking = false

    enum LoadState: Equatable {
        case loading
        case notConfigured
        case loaded
        case failed(String)
    }

    /// One completed action, wrapped so it can drive `.sheet(item:)`.
    struct OperationOutcome: Identifiable {
        let id = UUID()
        let title: String
        let results: [OperationResult]
    }

    /// The lifecycle actions available on an existing blueprint.
    ///
    /// Each one reaches production devices, so each carries the exact wording shown in its
    /// confirmation prompt.
    enum Action {
        case deploy
        case undeploy
        case delete

        var confirmTitle: String {
            switch self {
            case .deploy: return "Deploy Blueprint?"
            case .undeploy: return "Undeploy Blueprint?"
            case .delete: return "Delete Blueprint?"
            }
        }

        var actionTitle: String {
            switch self {
            case .deploy: return "Deploy"
            case .undeploy: return "Undeploy"
            case .delete: return "Delete"
            }
        }

        var role: ButtonRole? {
            switch self {
            case .deploy: return nil
            case .undeploy: return nil
            case .delete: return .destructive
            }
        }

        func message(for name: String) -> String {
            switch self {
            case .deploy:
                return "“\(name)” will be deployed. Jamf creates the declaration objects and queues a Declarative Management command for every device in the blueprint's scope, which applies the settings on those devices."
            case .undeploy:
                return "“\(name)” will be undeployed. Its declarations are withdrawn from every device currently in its scope, and the settings it applied stop being enforced."
            case .delete:
                return "“\(name)” will be permanently deleted. This cannot be undone, and the settings it applied are withdrawn from every device it is scoped to."
            }
        }

        /// Deploy and undeploy are accepted with a 202 — the server starts the work and finishes
        /// it afterwards — so the wording says what was requested, not what has completed.
        var resultTitle: String {
            switch self {
            case .deploy: return "Deployment Requested"
            case .undeploy: return "Undeployment Requested"
            case .delete: return "Blueprint Deleted"
            }
        }
    }

    private var filteredBlueprints: [Blueprint] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return blueprints }
        return blueprints.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .task {
            await load()
        }
        // Credentials are entered in Settings; reload once that sheet closes so the module
        // picks up a newly configured integration without needing a restart.
        .onChange(of: showConfigSheet) { _, isShowing in
            if !isShowing {
                Task { await load() }
            }
        }
        .sheet(item: $inspected) { blueprint in
            BlueprintInspectorView(blueprint: blueprint, api: api)
        }
        .sheet(item: $editor) { mode in
            BlueprintEditorSheet(mode: mode, api: api) {
                Task { await load() }
            }
        }
        .sheet(item: $outcome) { outcome in
            OperationResultView(title: outcome.title, results: outcome.results) {
                self.outcome = nil
            }
        }
        .commanderConfirmation(data: $confirmation)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search blueprints...", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search blueprints")

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Spacer()

            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button(action: { Task { await load() } }) {
                Image(systemName: "arrow.clockwise")
                    .frame(height: 18)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .help("Refresh blueprints")
            .accessibilityLabel("Refresh blueprints")

            Button(action: { editor = .create }) {
                Image(systemName: "plus")
                    .frame(height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!api.isPlatformConfigured || isWorking)
            .help("Create a blueprint from JSON")
            .accessibilityLabel("New blueprint")
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView("Loading Blueprints...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .notConfigured:
            notConfiguredView

        case .failed(let message):
            failedView(message)

        case .loaded:
            if blueprints.isEmpty {
                emptyView
            } else if filteredBlueprints.isEmpty {
                noMatchesView
            } else {
                blueprintList
            }
        }
    }

    private var blueprintList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredBlueprints) { blueprint in
                    BlueprintCardView(
                        blueprint: blueprint,
                        onInspect: { inspected = blueprint },
                        onEdit: { editor = .edit(blueprint) },
                        onDeploy: { confirm(.deploy, on: blueprint) },
                        onUndeploy: { confirm(.undeploy, on: blueprint) },
                        onDelete: { confirm(.delete, on: blueprint) }
                    )
                    .contextMenu {
                        Button("Inspect", systemImage: "magnifyingglass") { inspected = blueprint }
                        Button("Edit", systemImage: "square.and.pencil") { editor = .edit(blueprint) }
                        Divider()
                        Button("Deploy", systemImage: "arrow.up.circle") { confirm(.deploy, on: blueprint) }
                        Button("Undeploy", systemImage: "arrow.down.circle") { confirm(.undeploy, on: blueprint) }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { confirm(.delete, on: blueprint) }
                    }
                }
            }
            .padding()
        }
    }

    private var notConfiguredView: some View {
        ContentUnavailableView {
            Label("Blueprints Not Configured", systemImage: "key.slash")
        } description: {
            Text("Blueprints are served by Jamf's Platform API, which uses its own integration created in Jamf Account — separate from the Jamf Pro API client. Add its region, environment ID, client ID and secret in Settings.")
        } actions: {
            Button("Open Settings") { showConfigSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load Blueprints", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
            Button("Open Settings") { showConfigSheet = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Blueprints", systemImage: "square.stack.3d.up")
        } description: {
            Text("This platform environment has no blueprints yet.")
        } actions: {
            Button("New Blueprint") { editor = .create }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesView: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func load() async {
        guard api.isPlatformConfigured else {
            blueprints = []
            loadState = .notConfigured
            return
        }

        if blueprints.isEmpty {
            loadState = .loading
        }

        do {
            blueprints = try await api.fetchBlueprints()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Actions

    /// Puts the action behind an explicit confirmation naming the blueprint and the real effect.
    private func confirm(_ action: Action, on blueprint: Blueprint) {
        confirmation = ConfirmationData(
            title: action.confirmTitle,
            message: action.message(for: blueprint.name),
            actionTitle: action.actionTitle,
            role: action.role,
            action: { perform(action, on: blueprint) }
        )
    }

    /// Runs one action and reports exactly what the server said, success or failure, before
    /// refreshing so the list reflects the server rather than an assumption.
    private func perform(_ action: Action, on blueprint: Blueprint) {
        isWorking = true

        Task {
            let result: OperationResult

            do {
                switch action {
                case .deploy:
                    try await api.deployBlueprint(id: blueprint.id)
                case .undeploy:
                    try await api.undeployBlueprint(id: blueprint.id)
                case .delete:
                    try await api.deleteBlueprint(id: blueprint.id)
                }
                result = OperationResult(itemName: blueprint.name, success: true, error: nil)
            } catch {
                result = OperationResult(
                    itemName: blueprint.name,
                    success: false,
                    error: error.localizedDescription
                )
            }

            isWorking = false
            outcome = OperationOutcome(title: action.resultTitle, results: [result])
            await load()
        }
    }
}
