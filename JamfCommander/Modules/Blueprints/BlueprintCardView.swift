//
//  BlueprintCardView.swift
//  JamfCommander
//
//  One row in the Blueprints list. Presentational: the dashboard owns selection and actions.
//

import SwiftUI

struct BlueprintCardView: View {
    let blueprint: Blueprint

    /// Per-item actions, shown in the row's menu. The dashboard confirms them before running.
    var onInspect: () -> Void
    var onDeploy: () -> Void
    var onUndeploy: () -> Void
    var onDelete: () -> Void

    private var subtitle: String? {
        guard let description = blueprint.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }

    var body: some View {
        HStack(spacing: 14) {
            // The row body is its own button rather than a tap gesture on the whole card, so a
            // click on the actions menu beside it is never ambiguous.
            Button(action: onInspect) {
                HStack(spacing: 14) {
                    icon

                    VStack(alignment: .leading, spacing: 4) {
                        Text(blueprint.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Updated \(BlueprintDateParser.display(blueprint.updated))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    BlueprintDeploymentBadge(state: blueprint.deploymentStateText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(blueprint.name), \(blueprint.deploymentStateText)")
            .accessibilityHint("Opens the blueprint inspector")

            actionMenu
        }
        .padding()
        .liquidGlassRect(cornerRadius: 12)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 36, height: 36)

            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 15))
                .foregroundStyle(.blue)
        }
        .accessibilityHidden(true)
    }

    private var actionMenu: some View {
        Menu {
            Button("Inspect", systemImage: "magnifyingglass", action: onInspect)

            Divider()

            Button("Deploy", systemImage: "arrow.up.circle", action: onDeploy)
            Button("Undeploy", systemImage: "arrow.down.circle", action: onUndeploy)

            Divider()

            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions for this blueprint")
        .accessibilityLabel("Blueprint actions")
    }
}

// MARK: - Deployment badge

/// Shows the deployment state exactly as the server words it.
///
/// This is deliberately not `StatusBadge`: that renders a `JamfItemStatus`, whose labels are
/// "Scoped"/"Unscoped" and describe something else entirely. Only "DEPLOYED" and "SUCCEEDED"
/// appear in Jamf's published examples, so the colour and symbol are matched defensively and any
/// state the API adds later still displays, in neutral styling, rather than being mislabelled.
struct BlueprintDeploymentBadge: View {
    let state: String

    private var appearance: (colour: Color, icon: String) {
        let normalised = state.uppercased()

        if normalised.contains("FAIL") || normalised.contains("ERROR") {
            return (.red, "exclamationmark.triangle.fill")
        }
        if normalised.contains("PROGRESS") || normalised.contains("PENDING")
            || normalised.contains("DEPLOYING") || normalised.contains("QUEUED") {
            return (.orange, "clock.fill")
        }
        if normalised == "DEPLOYED" || normalised == "SUCCEEDED" {
            return (.green, "checkmark.circle.fill")
        }
        if normalised.isEmpty || normalised == "UNKNOWN" {
            return (.secondary, "questionmark.circle")
        }
        return (.secondary, "circle")
    }

    /// "NOT_DEPLOYED" reads as "Not Deployed" without inventing a different word for it.
    private var label: String {
        state
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appearance.icon)
                .font(.caption2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(appearance.colour)
        .background(appearance.colour.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(appearance.colour.opacity(0.3), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityLabel("Deployment state: \(label)")
    }
}
