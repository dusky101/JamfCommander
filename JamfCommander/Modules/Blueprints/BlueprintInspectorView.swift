//
//  BlueprintInspectorView.swift
//  JamfCommander
//
//  Read-only detail for one blueprint: summary fields plus the full definition as JSON.
//
//  The definition is shown as text rather than parsed into fields because a component's
//  `configuration` can carry any Apple payload key. Rendering it verbatim means nothing is
//  hidden from the administrator, and the text can be copied straight into the create sheet.
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
        InspectorShell(
            title: "BLUEPRINT",
            id: blueprint.id,
            headerText: blueprint.name,
            icon: "square.stack.3d.up.fill",
            isLoading: isLoading,
            onClose: { dismiss() }
        ) {
            content
        }
        .task {
            await loadDefinition()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            failureView(errorMessage)
        } else {
            VStack(spacing: 0) {
                summarySection
                Divider()
                JSONEditorView(title: "Definition", text: .constant(definition))
            }
        }
    }

    private var summarySection: some View {
        ScrollView {
            InfoSection(title: "Overview", icon: "info.circle") {
                InfoRow(label: "Deployment", value: blueprint.deploymentStateText)

                if let lastDeployment = blueprint.deploymentState?.lastDeployment {
                    InfoRow(
                        label: "Last deployment",
                        value: BlueprintDateParser.display(lastDeployment.started)
                    )
                    if let state = lastDeployment.state, !state.isEmpty {
                        InfoRow(label: "Outcome", value: state.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }

                InfoRow(label: "Created", value: BlueprintDateParser.display(blueprint.created))
                InfoRow(label: "Updated", value: BlueprintDateParser.display(blueprint.updated))

                if let description = blueprint.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(description)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: 230)
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could not load the definition", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await loadDefinition() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
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
