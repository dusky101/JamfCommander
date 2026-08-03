//
//  LabelVariantPanel.swift
//  JamfCommander
//
//  Explains what one Installomator label will actually do on a Mac, by reading the label's own
//  source. This exists because a label that branches on `$(arch)` looks like it needs a decision
//  from the administrator, when in fact the choice is made on each Mac at install time — the panel
//  says so plainly rather than leaving it to be guessed at.
//
//  Informational only. It never blocks or alters a deployment, and it degrades quietly when GitHub
//  is unreachable.
//

import SwiftUI

struct LabelVariantPanel: View {
    @ObservedObject var api: JamfAPIService
    let item: InstallomatorItem
    var onDismiss: () -> Void

    @State private var source: InstallomatorLabelSource?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 520, height: 460)
        .appBackground()
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                Text(item.label)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Done", action: onDismiss)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading the label from GitHub…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let source {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    behaviourSection(source)
                    detailSection(source)

                    Text("Read from \(source.sourcePath) in the Installomator repository. This is a description of the label, not a setting — nothing here changes what JamfCommander writes to Jamf.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cloud.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Couldn't read this label")
                    .font(.headline)
                Text(loadFailed
                     ? "GitHub could not be reached, or this label has no separate source file. Deployment is unaffected — this panel is informational only."
                     : "No details available for this label.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private func behaviourSection(_ source: InstallomatorLabelSource) -> some View {
        InfoSection(title: "What this label does", icon: "questionmark.circle") {
            explanation(
                icon: source.isArchitectureAware ? "cpu" : "desktopcomputer",
                tint: source.isArchitectureAware ? .green : .secondary,
                title: source.isArchitectureAware ? "Handles both architectures" : "One download for every Mac",
                detail: source.architectureSummary
            )

            Divider()

            explanation(
                icon: source.resolvesVersionAtRunTime ? "clock.arrow.circlepath" : "number",
                tint: source.resolvesVersionAtRunTime ? .blue : .secondary,
                title: source.resolvesVersionAtRunTime ? "Always installs the current version" : "Fixed version",
                detail: source.versionSummary
            )
        }
    }

    private func detailSection(_ source: InstallomatorLabelSource) -> some View {
        InfoSection(title: "Label details", icon: "doc.plaintext") {
            if let appName = source.appName {
                InfoRow(label: "Installs", value: appName)
            }
            if let type = source.type {
                InfoRow(label: "Package type", value: type.uppercased())
            }
            if let teamID = source.expectedTeamID {
                InfoRow(label: "Expected team ID", value: teamID)
            }
            if !source.blockingProcesses.isEmpty {
                InfoRow(label: "Blocking processes", value: source.blockingProcesses.joined(separator: ", "))
            }
        }
    }

    private func explanation(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            let fetched = try await api.fetchInstallomatorLabelSource(for: item.label)
            source = fetched
        } catch {
            source = nil
            loadFailed = true
        }
        isLoading = false
    }
}
