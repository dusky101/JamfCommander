//
//  ComputersDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ComputersDashboardView: View {
    @ObservedObject var api: JamfAPIService

    @State private var computers: [ComputerInventoryRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var inspectorSelection: InspectorSelection?

    // Filter State
    @State private var showManagedOnly = false

    // Table State
    @State private var selectedIds: Set<String> = []
    @State private var sortOrder: [KeyPathComparator<ComputerInventoryRecord>] = [
        KeyPathComparator(\ComputerInventoryRecord.sortName, order: .forward)
    ]

    // MARK: - Filtering & Sorting

    /// Apply text search and the managed-only filter chip.
    var filteredComputers: [ComputerInventoryRecord] {
        computers.filter { computer in
            let name = computer.general?.name ?? ""
            let serial = computer.hardware?.serialNumber ?? ""
            let user = computer.userAndLocation?.realname ?? computer.userAndLocation?.username ?? ""
            let email = computer.userAndLocation?.email ?? ""

            let matchesText = searchText.isEmpty ||
                name.localizedCaseInsensitiveContains(searchText) ||
                serial.localizedCaseInsensitiveContains(searchText) ||
                user.localizedCaseInsensitiveContains(searchText) ||
                email.localizedCaseInsensitiveContains(searchText)

            let isManaged = computer.general?.remoteManagement?.managed ?? false
            let matchesStatus = !showManagedOnly || isManaged

            return matchesText && matchesStatus
        }
    }

    /// Apply the current column sort to the filtered list.
    var sortedComputers: [ComputerInventoryRecord] {
        filteredComputers.sorted(using: sortOrder)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // --- Search & Filter Bar ---
            VStack(spacing: 12) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search by name, serial, user or email...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

                // Filter Chips
                HStack {
                    FilterChip(
                        title: "All Devices",
                        icon: "desktopcomputer.and.macbook",
                        selectedIcon: "desktopcomputer.and.macbook",
                        color: .blue,
                        isSelected: !showManagedOnly,
                        count: computers.count
                    ) { showManagedOnly = false }

                    FilterChip(
                        title: "Managed Only",
                        icon: "checkmark.seal",
                        selectedIcon: "checkmark.seal.fill",
                        color: .green,
                        isSelected: showManagedOnly,
                        count: computers.filter { $0.general?.remoteManagement?.managed ?? false }.count
                    ) { showManagedOnly = true }

                    Spacer()

                    Button(action: { exportComputers() }) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Export to CSV")

                    Button(action: { Task { await refreshData() } }) {
                        Image(systemName: "arrow.clockwise")
                            .frame(height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Data")
                }
            }
            .padding()
            .overlay(Divider().opacity(0.5), alignment: .bottom)
            .zIndex(1)

            // --- Table ---
            if isLoading {
                ProgressView("Scanning Fleet (Pro API)...")
                    .frame(maxHeight: .infinity)
            } else {
                computerTable
            }
        }
        .background(Color.clear)
        .task {
            await refreshData()
        }
        .sheet(item: $inspectorSelection) { selection in
            ComputerInspectorView(computerId: selection.id, api: api)
        }
    }

    // MARK: - Table

    private var computerTable: some View {
        Table(sortedComputers, selection: $selectedIds, sortOrder: $sortOrder) {
            TableColumn("Device", value: \ComputerInventoryRecord.sortName) { computer in
                deviceCell(computer)
            }
            .width(min: 180, ideal: 240)

            TableColumn("ID", value: \ComputerInventoryRecord.sortIntId) { computer in
                idCell(computer)
            }
            .width(min: 50, ideal: 60, max: 90)

            TableColumn("Model", value: \ComputerInventoryRecord.sortModel) { computer in
                modelCell(computer)
            }
            .width(min: 180, ideal: 240)

            TableColumn("Serial", value: \ComputerInventoryRecord.sortSerial) { computer in
                serialCell(computer)
            }
            .width(min: 120, ideal: 140)

            TableColumn("User", value: \ComputerInventoryRecord.sortRealName) { computer in
                userCell(computer)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Last Contact", value: \ComputerInventoryRecord.sortLastContact) { computer in
                lastContactCell(computer)
            }
            .width(min: 130, ideal: 160)

            TableColumn("Status", value: \ComputerInventoryRecord.sortManagedRank) { computer in
                statusBadge(isManaged: computer.general?.remoteManagement?.managed ?? false)
            }
            .width(min: 90, ideal: 100, max: 120)
        }
        .contextMenu(forSelectionType: ComputerInventoryRecord.ID.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            // Triggered on double-click or Return key.
            if let id = ids.first, let computer = sortedComputers.first(where: { $0.id == id }) {
                open(computer: computer)
            }
        }
    }

    // MARK: - Cell builders

    @ViewBuilder
    private func deviceCell(_ computer: ComputerInventoryRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: DeviceSymbols.iconName(for: computer.hardware?.model ?? "Mac"))
                .foregroundColor((computer.general?.remoteManagement?.managed ?? false) ? .blue : .orange)
            Text(computer.general?.name ?? "Unknown Device")
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func idCell(_ computer: ComputerInventoryRecord) -> some View {
        Text(computer.id)
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func serialCell(_ computer: ComputerInventoryRecord) -> some View {
        Text(computer.hardware?.serialNumber ?? "—")
            .font(.caption)
            .fontDesign(.monospaced)
            .lineLimit(1)
    }

    @ViewBuilder
    private func lastContactCell(_ computer: ComputerInventoryRecord) -> some View {
        Text(formattedLastContact(computer.general?.lastContactTime))
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func modelCell(_ computer: ComputerInventoryRecord) -> some View {
        Text(computer.hardware?.model ?? "—")
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func userCell(_ computer: ComputerInventoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(userDisplayName(computer))
                .lineLimit(1)
                .truncationMode(.tail)
            if let email = computer.userAndLocation?.email, !email.isEmpty {
                Text(email)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(isManaged: Bool) -> some View {
        Text(isManaged ? "Managed" : "Unmanaged")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isManaged ? Color.green : Color.orange).opacity(0.15))
            .foregroundColor(isManaged ? .green : .orange)
            .cornerRadius(6)
    }

    @ViewBuilder
    private func contextMenuContent(for ids: Set<ComputerInventoryRecord.ID>) -> some View {
        if let id = ids.first, let computer = sortedComputers.first(where: { $0.id == id }) {
            Button("Inspect") { open(computer: computer) }
            Divider()
            if let serial = computer.hardware?.serialNumber {
                Button("Copy Serial: \(serial)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(serial, forType: .string)
                }
            }
        }
    }

    private func userDisplayName(_ computer: ComputerInventoryRecord) -> String {
        if let realname = computer.userAndLocation?.realname, !realname.isEmpty { return realname }
        if let username = computer.userAndLocation?.username, !username.isEmpty { return username }
        return "—"
    }

    // MARK: - Helpers

    /// Format Jamf's ISO 8601 `lastContactTime` for the table. Falls back to the raw value
    /// if it cannot be parsed, and to an em dash when missing entirely.
    private func formattedLastContact(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return raw
    }

    private func open(computer: ComputerInventoryRecord) {
        inspectorSelection = InspectorSelection(id: computer.intId)
    }

    // MARK: - Actions

    func refreshData() async {
        do {
            let list = try await api.fetchComputers()
            self.computers = list
            self.isLoading = false
        } catch {
            print("Error loading computers: \(error)")
            self.isLoading = false
        }
    }

    private func exportComputers() {
        Task {
            let csvContent = await ExportService.exportComputersToCSV(computers: computers, api: api)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = dateFormatter.string(from: Date())
            _ = await MainActor.run {
                ExportService.saveCSVToFile(content: csvContent, defaultName: "Computers_\(dateString).csv")
            }
        }
    }
}

// MARK: - Sort helpers
// Non-optional projections used as KeyPathComparator key paths. SwiftUI's
// `KeyPathComparator` needs a non-optional `Comparable` value path, so we
// surface stable empty-string / zero / false fallbacks here.
extension ComputerInventoryRecord {
    var sortName: String { general?.name ?? "" }
    var sortModel: String { hardware?.model ?? "" }
    var sortSerial: String { hardware?.serialNumber ?? "" }
    var sortRealName: String {
        userAndLocation?.realname?.isEmpty == false ? (userAndLocation?.realname ?? "") :
        (userAndLocation?.username ?? "")
    }
    var sortEmail: String { userAndLocation?.email ?? "" }
    var sortLastContact: String { general?.lastContactTime ?? "" }
    /// 1 = managed, 0 = unmanaged. Int-typed so it shares a `V` type with `sortIntId`,
    /// which helps SwiftUI's @TableColumnBuilder unify column types.
    var sortManagedRank: Int { (general?.remoteManagement?.managed ?? false) ? 1 : 0 }
    var sortIntId: Int { intId }
}
