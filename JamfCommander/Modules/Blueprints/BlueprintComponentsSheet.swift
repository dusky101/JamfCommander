//
//  BlueprintComponentsSheet.swift
//  JamfCommander
//
//  Browses the component catalogue this platform environment offers.
//
//  A blueprint's `steps[].components[].identifier` must be one of these, and the catalogue is
//  tenant- and version-dependent — Jamf ships components ahead of the API reference listing them.
//  Reading it here is how you find out what is genuinely available (and what shape its
//  `configuration` takes) without guessing from documentation.
//

import SwiftUI

struct BlueprintComponentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var api: JamfAPIService

    @State private var components: [BlueprintComponent] = []
    @State private var loadState: LoadState = .loading
    @State private var search = ""
    @State private var selected: BlueprintComponent?
    @State private var detail = ""
    @State private var detailError: String?
    @State private var isLoadingDetail = false
    @State private var isShowingRawList = false

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private var filteredComponents: [BlueprintComponent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return components }
        return components.filter {
            $0.identifier.localizedCaseInsensitiveContains(query)
                || ($0.name ?? "").localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var detailTitle: String {
        if isShowingRawList { return "Raw List Response" }
        return selected?.displayTitle ?? "Component"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content

            Divider()

            footer
        }
        .frame(minWidth: 840, idealWidth: 1020, minHeight: 560, idealHeight: 720)
        .liquidGlass(cornerRadius: 16)
        .task {
            await load()
        }
        .onChange(of: selected) { _, newValue in
            guard let newValue else { return }
            isShowingRawList = false
            Task { await loadDetail(for: newValue) }
        }
    }

    // MARK: - Header & footer

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("BLUEPRINT COMPONENTS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text("Available in this environment")
                    .font(.headline)
            }

            Spacer(minLength: 16)

            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var footer: some View {
        HStack {
            if case .loaded = loadState {
                Text(
                    components.count == 1
                        ? "1 component"
                        : "\(components.count) components"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await loadRawList() }
            } label: {
                Label("Raw List Response", systemImage: "curlybraces")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Show the whole component-list response, including anything the app does not model")
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView("Loading components...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("Could Not Load Components", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded:
            HSplitView {
                listPane
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
                    .frame(maxHeight: .infinity)

                detailPane
                    .frame(minWidth: 420, maxWidth: .infinity)
            }
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Search components...", text: $search)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .accessibilityLabel("Search components")

                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear component search")
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)

            Divider()

            if filteredComponents.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredComponents, selection: $selected) { component in
                    row(for: component)
                        .tag(component)
                }
                .listStyle(.inset)
            }
        }
    }

    private func row(for component: BlueprintComponent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(component.displayTitle)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(component.identifier)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let description = component.description?
                .trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .help(component.identifier)
    }

    @ViewBuilder
    private var detailPane: some View {
        if isLoadingDetail {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Fetching component...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detailError {
            ContentUnavailableView {
                Label("Could Not Load That Component", systemImage: "exclamationmark.triangle")
            } description: {
                Text(detailError)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if detail.isEmpty {
            ContentUnavailableView {
                Label("Select A Component", systemImage: "sidebar.left")
            } description: {
                Text("Its full definition appears here, including the shape its configuration object takes.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            JSONEditorView(title: detailTitle, text: .constant(detail))
        }
    }

    // MARK: - Loading

    private func load() async {
        loadState = .loading

        do {
            components = try await api.fetchBlueprintComponents()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func loadDetail(for component: BlueprintComponent) async {
        isLoadingDetail = true
        detailError = nil

        do {
            detail = try await api.fetchBlueprintComponentJSON(identifier: component.identifier)
        } catch {
            detail = ""
            detailError = error.localizedDescription
        }

        isLoadingDetail = false
    }

    private func loadRawList() async {
        isLoadingDetail = true
        detailError = nil
        isShowingRawList = true
        selected = nil

        do {
            detail = try await api.fetchBlueprintComponentsRawJSON()
        } catch {
            detail = ""
            detailError = error.localizedDescription
        }

        isLoadingDetail = false
    }
}
