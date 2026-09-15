//
//  ScopeTargetPicker.swift
//  JamfCommander
//
//  The "what does this policy deploy to" control: the scope-type selector plus the computer or
//  computer-group list that goes with it.
//
//  Extracted because three flows now scope a policy — creating Installomator policies, editing a
//  deployed one, and uploading a custom package — and three copies of a searchable multi-select list
//  is two too many.
//
//  It owns no data. Each flow loads computers and groups at a different moment (the deployment sheet
//  up front, the editor only once the administrator opts into changing the scope), so the caller
//  supplies them and binds the `DeploymentScopeConfig` being edited.
//

import SwiftUI

struct ScopeTargetPicker: View {
    @Binding var scope: DeploymentScopeConfig
    let computers: [ComputerInventoryRecord]
    let groups: [ComputerGroup]

    /// Shown under "All Computers". Worth varying: creating a policy and retargeting an existing one
    /// mean different things by the same scope.
    var allComputersNote: String = "The policy will be scoped to all managed computers."

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Scope", selection: $scope.scopeType) {
                ForEach(DeploymentScopeType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: scope.scopeType) {
                searchText = ""
                scope.selectedGroupIDs.removeAll()
            }

            switch scope.scopeType {
            case .allComputers:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text(allComputersNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
                .accessibilityElement(children: .combine)

            case .specificComputers:
                computerPicker

            case .smartComputerGroups, .staticComputerGroups:
                groupPicker
            }
        }
    }

    // MARK: - Computers

    /// Searched on the same rule as the Computers dashboard — name, serial, assigned user or email —
    /// so a Mac can be found by whoever it belongs to.
    private var filteredComputers: [ComputerInventoryRecord] {
        computers.filter { $0.matches(searchText) }
    }

    private var computerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField("Search by name, serial, user or email...", label: "Search computers")

            if !scope.selectedComputerIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer").foregroundColor(.blue)
                    Text("\(scope.selectedComputerIDs.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { scope.selectedComputerIDs.removeAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                }
            }

            targetList {
                if filteredComputers.isEmpty {
                    emptyRow(searchText.isEmpty ? "No computers found." : "No computers match “\(searchText)”.")
                }

                ForEach(filteredComputers) { computer in
                    let isSelected = scope.selectedComputerIDs.contains(computer.id)
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
                            scope.selectedComputerIDs.remove(computer.id)
                        } else {
                            scope.selectedComputerIDs.insert(computer.id)
                        }
                    }
                    // The whole row is the toggle, so expose it as one selectable element rather
                    // than an unlabelled tick beside some text.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint("Adds or removes this computer from the scope")
                }
            }
        }
    }

    // MARK: - Groups

    private var filteredGroups: [ComputerGroup] {
        let groupsForScope = groups.filter { group in
            switch scope.scopeType {
            case .smartComputerGroups: return group.smartGroup == true
            case .staticComputerGroups: return group.smartGroup != true
            case .allComputers, .specificComputers: return false
            }
        }
        if searchText.isEmpty { return groupsForScope }
        return groupsForScope.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField("Search \(scope.scopeType.rawValue.lowercased())...", label: "Search groups")

            if !scope.selectedGroupIDs.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill").foregroundColor(.blue)
                    Text("\(scope.selectedGroupIDs.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { scope.selectedGroupIDs.removeAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                }
            }

            targetList {
                if filteredGroups.isEmpty {
                    emptyRow(searchText.isEmpty
                             ? "No \(scope.scopeType.rawValue.lowercased()) found."
                             : "No groups match “\(searchText)”.")
                }

                ForEach(filteredGroups) { group in
                    let isSelected = scope.selectedGroupIDs.contains(group.id)
                    Button {
                        if isSelected {
                            scope.selectedGroupIDs.remove(group.id)
                        } else {
                            scope.selectedGroupIDs.insert(group.id)
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
    }

    // MARK: - Shared pieces

    private func searchField(_ prompt: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(prompt, text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel(label)
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }

    private func targetList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(spacing: 2, content: content)
        }
        .frame(maxHeight: 150)
        .liquidGlassRect(cornerRadius: 6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
    }
}
