//
//  BlueprintInspectorView.swift
//  JamfCommander
//
//  Read-only detail for one blueprint: summary fields beside the full definition as JSON.
//
//  The definition is shown as text rather than parsed into fields because a component's
//  `configuration` can carry any Apple payload key. Rendering it verbatim means nothing is
//  hidden from the administrator, and the text can be copied straight into the create sheet.
//
//  This does not use `InspectorShell`, for the same reason `ScriptInspectorView` does not: the
//  main content is a wide monospaced document, and the shell is fixed at 500pt. The shell also
//  lays its header out as a ZStack, so a long identifier runs underneath the centred title —
//  see docs/cleanup.md.
//

import SwiftUI

struct BlueprintInspectorView: View {
    @Environment(\.dismiss) private var dismiss

    let blueprint: Blueprint
    @ObservedObject var api: JamfAPIService

    @State private var definition = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .frame(minWidth: 780, idealWidth: 960, minHeight: 540, idealHeight: 700)
        .liquidGlass(cornerRadius: 16)
        .task {
            await loadDefinition()
        }
    }

    // MARK: - Header

    /// Laid out as a single HStack with a Spacer, so the name, the identifier and the Close
    /// button reserve their own width and cannot overlap however long the name or the UUID is.
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("BLUEPRINT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(blueprint.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 16)

            BlueprintDeploymentBadge(state: blueprint.deploymentStateText)

            Text(blueprint.id)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: 230, alignment: .trailing)
                .help("Blueprint identifier")
                .accessibilityLabel("Blueprint identifier \(blueprint.id)")

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let errorMessage {
            failureView(errorMessage)
        } else {
            HSplitView {
                overviewPane
                    .frame(minWidth: 280, idealWidth: 330, maxWidth: 420)
                    .frame(maxHeight: .infinity)

                JSONEditorView(title: "Definition", text: .constant(definition))
                    .frame(minWidth: 400, maxWidth: .infinity)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Fetching blueprint definition...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Sized by its content rather than a fixed height, so a blueprint with no description does
    /// not leave a band of empty space above the definition.
    private var overviewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(title: "Overview", icon: "info.circle") {
                    InfoRow(label: "Deployment", value: blueprint.deploymentStateText)
                    InfoRow(label: "Created", value: BlueprintDateParser.display(blueprint.created))
                    InfoRow(label: "Updated", value: BlueprintDateParser.display(blueprint.updated))
                }

                if let lastDeployment = blueprint.deploymentState?.lastDeployment,
                   lastDeployment.started != nil || lastDeployment.state != nil {
                    InfoSection(title: "Last Deployment", icon: "arrow.up.circle") {
                        InfoRow(
                            label: "Started",
                            value: BlueprintDateParser.display(lastDeployment.started)
                        )
                        if let state = lastDeployment.state, !state.isEmpty {
                            InfoRow(label: "Outcome", value: Self.humanise(state))
                        }
                    }
                }

                if let description = blueprint.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    InfoSection(title: "Description", icon: "text.alignleft") {
                        Text(description)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load The Definition", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await loadDefinition() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// "NOT_DEPLOYED" reads as "Not Deployed" without substituting a different word for it.
    private static func humanise(_ state: String) -> String {
        state.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Loading

    private func loadDefinition() async {
        isLoading = true
        errorMessage = nil

        do {
            definition = try await api.fetchBlueprintJSON(id: blueprint.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
