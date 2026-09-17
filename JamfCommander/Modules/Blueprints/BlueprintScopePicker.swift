//
//  BlueprintScopePicker.swift
//  JamfCommander
//
//  Device-group selection for a blueprint's scope.
//
//  These are platform device groups, identified by UUID and fetched from the Platform API. They
//  are a different set from the numeric Jamf Pro computer groups in `ScopeTargetPicker`, which is
//  why that component is not reused here — a Jamf Pro group ID is not accepted in
//  `scope.deviceGroups`.
//

import SwiftUI

struct BlueprintScopePicker: View {
    let groups: [PlatformDeviceGroup]
    @Binding var selection: Set<String>

    @State private var search = ""

    private var filteredGroups: [PlatformDeviceGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if groups.isEmpty {
                Text("No device groups were returned for this environment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if filteredGroups.isEmpty {
                Text("No groups match “\(search)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                groupList
            }

            selectionSummary
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search groups...", text: $search)
                .textFieldStyle(.plain)
                .font(.caption)
                .accessibilityLabel("Search device groups")

            if !search.isEmpty {
                Button(action: { search = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear group search")
            }
        }
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredGroups) { group in
                    row(for: group)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 190)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        .cornerRadius(6)
    }

    private func row(for group: PlatformDeviceGroup) -> some View {
        Toggle(isOn: binding(for: group.id)) {
            HStack(spacing: 8) {
                Image(systemName: group.deviceTypeIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !group.summary.isEmpty {
                        Text(group.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .help(group.id)
        .accessibilityHint("Device group identifier \(group.id)")
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if selection.isEmpty {
            Label("No groups selected", systemImage: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 6) {
                Label(
                    selection.count == 1 ? "1 group selected" : "\(selection.count) groups selected",
                    systemImage: "checkmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Clear") { selection.removeAll() }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Helpers

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn {
                    selection.insert(id)
                } else {
                    selection.remove(id)
                }
            }
        )
    }
}
