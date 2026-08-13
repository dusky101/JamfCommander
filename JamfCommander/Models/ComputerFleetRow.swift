//
//  ComputerFleetRow.swift
//  JamfCommander
//
//  One Mac as both Jamf Pro and Apple Business Manager see it.
//

import Foundation

/// A Jamf computer joined to its Apple Business Manager record.
///
/// **The join runs outward from Jamf, never the reverse.** Jamf holds Macs that never passed through
/// ABM — retail purchases, warranty replacements, machines released from the organisation — and a row
/// with no ABM match must read "Not in Apple Business Manager" rather than vanish from the list.
///
/// The Jamf sort projections are forwarded so `Table` column key paths stay short, and the ABM ones
/// are derived here so the table, the inspector and the export cannot disagree about a date.
/// Unlike the `ABM…` models this is **not** `nonisolated`: it wraps `ComputerInventoryRecord`, it is
/// only ever built and read on the main actor by the table and the inspector, and it never crosses
/// into `ABMCache`. Marking it otherwise makes its conformances unusable from the isolation its own
/// members belong to.
struct ComputerFleetRow: Identifiable, Hashable {

    let computer: ComputerInventoryRecord
    /// `nil` when ABM has no record for this serial.
    let abm: ABMDeviceRecord?
    /// The configured lifecycle interval, carried so the derived date changes with the setting
    /// without needing a refetch.
    let lifecycleYears: Int

    var id: String { computer.id }

    var serialNumber: String? { computer.hardware?.serialNumber }

    // MARK: - Jamf projections
    //
    // Forwarded so the table's existing columns keep short key paths.

    var sortName: String { computer.sortName }
    var sortModel: String { computer.sortModel }
    var sortSerial: String { computer.sortSerial }
    var sortRealName: String { computer.sortRealName }
    var sortLastContact: String { computer.sortLastContact }
    var sortManagedRank: Int { computer.sortManagedRank }
    var sortIntId: Int { computer.intId }

    // MARK: - Apple Business Manager values

    var purchaseDate: Date? { abm?.purchaseDate }
    var purchaseDateSource: ABMPurchaseDateSource? { abm?.purchaseDateSource }
    var warrantyEndDate: Date? { abm?.warrantyEndDate }
    var lifecycleDate: Date? { abm?.lifecycleDate(years: lifecycleYears) }
    var warrantyState: ABMWarrantyState? { abm?.warrantyState }

    /// Whether cover has lapsed. A device with no ABM record, or whose warranty could not be
    /// fetched, is deliberately **not** counted as out of warranty — that would report a gap in the
    /// data as a fact about the machine.
    var isOutOfWarranty: Bool {
        guard let state = warrantyState else { return false }
        switch state {
        case .expired:
            return true
        case .active(let end):
            // Apple's status field has been seen lagging the date it reports; the date is what an
            // administrator acts on.
            guard let end else { return false }
            return end < Date()
        case .noRecord, .unavailable:
            return false
        }
    }

    var isPastLifecycle: Bool {
        abm?.isPastLifecycle(years: lifecycleYears) ?? false
    }

    func daysRemaining(from reference: Date = Date()) -> Int? {
        abm?.daysRemaining(from: reference)
    }

    // MARK: - Sort projections
    //
    // `Table` needs a non-optional `Comparable`. Rows with nothing to sort on are pushed to the far
    // end rather than mixed in with real dates, so a sort by warranty always groups the unknowns.

    var sortPurchaseDate: Date { purchaseDate ?? .distantPast }
    var sortWarrantyEnd: Date { warrantyEndDate ?? .distantFuture }
    var sortLifecycleDate: Date { lifecycleDate ?? .distantFuture }

    // MARK: - Display

    var purchaseDateText: String {
        guard abm != nil else { return "—" }
        guard let purchaseDate else { return "Unknown" }
        return Self.dateText(purchaseDate)
    }

    var warrantyText: String {
        guard let state = warrantyState else { return "—" }
        switch state {
        case .active(let end), .expired(let end):
            guard let end else { return "Unknown" }
            return Self.dateText(end)
        case .noRecord:
            return "No record"
        case .unavailable:
            return "Unavailable"
        }
    }

    var lifecycleText: String {
        guard abm != nil else { return "—" }
        guard let lifecycleDate else { return "Unknown" }
        return Self.dateText(lifecycleDate)
    }

    /// Cover state in words, for the inspector.
    var warrantyDetailText: String {
        guard let state = warrantyState else {
            return "Not in Apple Business Manager"
        }

        switch state {
        case .active(let end):
            guard let end else { return "In warranty" }
            guard let days = daysRemaining() else { return Self.dateText(end) }
            if days < 0 {
                return "\(Self.dateText(end)) — lapsed \(abs(days)) day\(abs(days) == 1 ? "" : "s") ago"
            }
            return "\(Self.dateText(end)) — \(days) day\(days == 1 ? "" : "s") remaining"
        case .expired(let end):
            guard let end else { return "Out of warranty" }
            return "\(Self.dateText(end)) — out of warranty"
        case .noRecord:
            return "No warranty record held by Apple"
        case .unavailable:
            return "Could not be retrieved — refresh Apple Business Manager data"
        }
    }

    static func dateText(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension ComputerFleetRow {

    /// Joins a Jamf list to the cached ABM fleet. Every Jamf record produces a row.
    static func rows(
        for computers: [ComputerInventoryRecord],
        fleet: ABMFleetStore,
        lifecycleYears: Int
    ) -> [ComputerFleetRow] {
        computers.map { computer in
            ComputerFleetRow(
                computer: computer,
                abm: fleet.record(for: computer.hardware?.serialNumber),
                lifecycleYears: lifecycleYears
            )
        }
    }
}
