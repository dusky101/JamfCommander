//
//  ComputersDashboardView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

struct ComputersDashboardView: View {
    @ObservedObject var api: JamfAPIService
    /// Cached Apple Business Manager data. Read only — the table never triggers a request per row.
    @ObservedObject private var fleet = ABMFleetStore.shared

    @AppStorage("abmLifecycleYears") private var lifecycleYears = 4

    @State private var computers: [ComputerInventoryRecord] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var inspectorSelection: InspectorSelection?

    /// The three chips are mutually exclusive, so one selection rather than a set of flags.
    enum FleetFilter {
        case all, managed, outOfWarranty
    }

    @State private var filter: FleetFilter = .all

    // Table State
    @State private var selectedIds: Set<String> = []
    @State private var columnCustomization = TableColumnCustomization<ComputerFleetRow>()
    @State private var sortOrder: [KeyPathComparator<ComputerFleetRow>] = [
        KeyPathComparator(\ComputerFleetRow.sortName, order: .forward)
    ]

    /// Whether the Apple Business Manager columns have anything to show. When ABM is not configured
    /// they are hidden entirely rather than filled with dashes.
    private var showsABMColumns: Bool {
        fleet.isConfigured
    }

    // MARK: - Joining, filtering & sorting

    /// Every Jamf computer, with its ABM record attached where one exists. The join runs outward from
    /// Jamf: a Mac ABM has never seen still gets a row.
    private var rows: [ComputerFleetRow] {
        ComputerFleetRow.rows(for: computers, fleet: fleet, lifecycleYears: lifecycleYears)
    }

    private var filteredRows: [ComputerFleetRow] {
        rows.filter { row in
            guard row.computer.matches(searchText) else { return false }

            switch filter {
            case .all: return true
            case .managed: return row.computer.isManaged
            case .outOfWarranty: return row.isOutOfWarranty
            }
        }
    }

    private var sortedRows: [ComputerFleetRow] {
        filteredRows.sorted(using: sortOrder)
    }

    private var outOfWarrantyCount: Int {
        rows.filter(\.isOutOfWarranty).count
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
                        isSelected: filter == .all,
                        count: computers.count
                    ) { filter = .all }

                    FilterChip(
                        title: "Managed Only",
                        icon: "checkmark.seal",
                        selectedIcon: "checkmark.seal.fill",
                        color: .green,
                        isSelected: filter == .managed,
                        count: computers.filter(\.isManaged).count
                    ) { filter = .managed }

                    if showsABMColumns {
                        FilterChip(
                            title: "Out of Warranty",
                            icon: "shield.slash",
                            selectedIcon: "shield.slash.fill",
                            color: .orange,
                            isSelected: filter == .outOfWarranty,
                            count: outOfWarrantyCount
                        ) { filter = .outOfWarranty }
                    }

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
            // The cached ABM fleet loads alongside the Jamf list; it is a file read, not a fetch.
            async let jamf: Void = refreshData()
            async let abm: Void = fleet.loadFromCache()
            _ = await (jamf, abm)
        }
        .sheet(item: $inspectorSelection) { selection in
            ComputerInspectorView(computerId: selection.id, api: api)
        }
    }

    // MARK: - Table

    private var computerTable: some View {
        Table(
            sortedRows,
            selection: $selectedIds,
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("Device", value: \ComputerFleetRow.sortName) { row in
                ComputerDeviceLabel(computer: row.computer)
            }
            .width(min: 180, ideal: 240)
            .customizationID("device")

            TableColumn("ID", value: \ComputerFleetRow.sortIntId) { row in
                idCell(row.computer)
            }
            .width(min: 50, ideal: 60, max: 90)
            .customizationID("id")

            TableColumn("Model", value: \ComputerFleetRow.sortModel) { row in
                modelCell(row)
            }
            .width(min: 180, ideal: 240)
            .customizationID("model")

            TableColumn("Serial", value: \ComputerFleetRow.sortSerial) { row in
                serialCell(row.computer)
            }
            .width(min: 120, ideal: 140)
            .customizationID("serial")

            TableColumn("User", value: \ComputerFleetRow.sortRealName) { row in
                ComputerUserLabel(computer: row.computer)
            }
            .width(min: 160, ideal: 220)
            .customizationID("user")

            TableColumn("Last Contact", value: \ComputerFleetRow.sortLastContact) { row in
                lastContactCell(row.computer)
            }
            .width(min: 130, ideal: 160)
            .customizationID("lastContact")

            TableColumn("Status", value: \ComputerFleetRow.sortManagedRank) { row in
                statusBadge(isManaged: row.computer.isManaged)
            }
            .width(min: 90, ideal: 100, max: 120)
            .customizationID("status")

            TableColumn("Purchased", value: \ComputerFleetRow.sortPurchaseDate) { row in
                purchaseCell(row)
            }
            .width(min: 110, ideal: 130)
            .customizationID("purchased")
            .defaultVisibility(showsABMColumns ? .visible : .hidden)

            TableColumn("Warranty Ends", value: \ComputerFleetRow.sortWarrantyEnd) { row in
                warrantyCell(row)
            }
            .width(min: 120, ideal: 140)
            .customizationID("warranty")
            .defaultVisibility(showsABMColumns ? .visible : .hidden)

            TableColumn("Lifecycle", value: \ComputerFleetRow.sortLifecycleDate) { row in
                lifecycleCell(row)
            }
            .width(min: 110, ideal: 130)
            .customizationID("lifecycle")
            .defaultVisibility(showsABMColumns ? .visible : .hidden)
        }
        .contextMenu(forSelectionType: ComputerFleetRow.ID.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            // Triggered on double-click or Return key.
            if let id = ids.first, let row = sortedRows.first(where: { $0.id == id }) {
                open(computer: row.computer)
            }
        }
    }

    // MARK: - Cell builders

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

    /// Prefers Apple Business Manager's marketing name ("MacBook Pro (16-inch, Nov 2024)") over
    /// Jamf's, which is less consistently formatted. Falls back to Jamf when ABM has no record.
    @ViewBuilder
    private func modelCell(_ row: ComputerFleetRow) -> some View {
        Text(row.abm?.attributes.deviceModel ?? row.computer.hardware?.model ?? "—")
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func purchaseCell(_ row: ComputerFleetRow) -> some View {
        HStack(spacing: 4) {
            Text(row.purchaseDateText)
                .font(.caption)
            // An inferred date must never look like a known one.
            if let source = row.purchaseDateSource, !source.isReliable, row.purchaseDate != nil {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .help("Inferred: \(source.displayName)")
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func warrantyCell(_ row: ComputerFleetRow) -> some View {
        Text(row.warrantyText)
            .font(.caption)
            .foregroundColor(row.isOutOfWarranty ? .orange : .primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func lifecycleCell(_ row: ComputerFleetRow) -> some View {
        Text(row.lifecycleText)
            .font(.caption)
            .foregroundColor(row.isPastLifecycle ? .orange : .primary)
            .lineLimit(1)
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
    private func contextMenuContent(for ids: Set<ComputerFleetRow.ID>) -> some View {
        if let id = ids.first, let row = sortedRows.first(where: { $0.id == id }) {
            Button("Inspect") { open(computer: row.computer) }
            Divider()
            if let serial = row.computer.hardware?.serialNumber {
                Button("Copy Serial: \(serial)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(serial, forType: .string)
                }
            }
        }
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
