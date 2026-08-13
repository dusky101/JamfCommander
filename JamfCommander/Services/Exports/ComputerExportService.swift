//
//  ComputerExportService.swift
//  JamfCommander
//
//  Computer export functionality

import Foundation

class ComputerExportService {

    /// The Jamf columns, always written.
    private static let jamfHeaders = [
        "ID", "Name", "Serial Number", "Model", "IP Address", "Last Contact", "Managed",
        "Management Username", "Username", "Real Name", "Email", "Position", "Phone",
        "Department", "Building", "Room"
    ]

    /// The Apple Business Manager columns, appended only when there is ABM data to put in them.
    private static let abmHeaders = [
        "ABM Model", "Product Type", "Capacity", "Colour", "Purchase Date", "Purchase Date Source",
        "Purchase Source", "Order Number", "Warranty", "Warranty Start", "Warranty End",
        "Warranty Status", "Lifecycle Date", "Added to ABM", "ABM Status", "Released From ABM"
    ]

    /// Export computers to CSV format.
    ///
    /// Includes hardware/management columns plus User & Location columns. Department and
    /// Building IDs are resolved to names when the lookup dictionaries are supplied.
    ///
    /// When `abmRecords` is non-empty, Apple Business Manager columns are appended — purchase date
    /// and **the source it was derived from**, warranty, and the calculated lifecycle date. This is
    /// the join the whole integration exists for: ABM knows what a Mac cost and when its cover ends
    /// but not who has it; Jamf knows who has it but neither of the others.
    ///
    /// The columns are omitted entirely when ABM is not in use, rather than padding every row of
    /// everyone else's export with sixteen empty fields.
    static func exportToCSV(
        computers: [ComputerInventoryRecord],
        buildings: [String: String] = [:],
        departments: [String: String] = [:],
        abmRecords: [String: ABMDeviceRecord] = [:],
        lifecycleYears: Int = 4
    ) -> String {
        let includesABM = !abmRecords.isEmpty
        let headers = includesABM ? jamfHeaders + abmHeaders : jamfHeaders

        var csv = headers.joined(separator: ",") + "\n"

        for computer in computers.sorted(by: { ($0.general?.name ?? "") < ($1.general?.name ?? "") }) {
            var fields = jamfFields(for: computer, buildings: buildings, departments: departments)

            if includesABM {
                let serial = computer.hardware?.serialNumber
                let record = serial.flatMap { abmRecords[$0] }
                fields += abmFields(for: record, lifecycleYears: lifecycleYears)
            }

            // Fields are assembled as an array and escaped uniformly. With thirty-two columns,
            // interpolating a row by hand is how a value ends up under the wrong heading.
            csv += fields.map(ExportHelpers.escapeCSV).joined(separator: ",") + "\n"
        }

        return csv
    }

    // MARK: - Jamf columns

    private static func jamfFields(
        for computer: ComputerInventoryRecord,
        buildings: [String: String],
        departments: [String: String]
    ) -> [String] {
        let user = computer.userAndLocation

        let departmentName: String = {
            guard let depId = user?.departmentId, !depId.isEmpty else { return "" }
            return departments[depId] ?? depId
        }()
        let buildingName: String = {
            guard let bldId = user?.buildingId, !bldId.isEmpty else { return "" }
            return buildings[bldId] ?? bldId
        }()

        return [
            computer.id,
            computer.general?.name ?? "Unknown",
            computer.hardware?.serialNumber ?? "N/A",
            computer.hardware?.model ?? "N/A",
            computer.general?.lastIpAddress ?? computer.general?.lastReportedIp ?? "N/A",
            computer.general?.lastContactTime ?? "N/A",
            computer.general?.remoteManagement?.managed == true ? "Yes" : "No",
            computer.general?.remoteManagement?.managementUsername ?? "N/A",
            user?.username ?? "",
            user?.realname ?? "",
            user?.email ?? "",
            user?.position ?? "",
            user?.phone ?? "",
            departmentName,
            buildingName,
            user?.room ?? ""
        ]
    }

    // MARK: - Apple Business Manager columns

    private static func abmFields(for record: ABMDeviceRecord?, lifecycleYears: Int) -> [String] {
        guard let record else {
            // A Mac Jamf manages that ABM has no record of. The status says so explicitly rather
            // than leaving a row of blanks that reads like missing data.
            //
            // Positioned by looking the heading up rather than counting: an offset written by hand
            // silently files a value under the wrong column, and stays wrong if the headings change.
            var empty = Array(repeating: "", count: abmHeaders.count)
            if let statusIndex = abmHeaders.firstIndex(of: "Warranty Status") {
                empty[statusIndex] = "NOT_IN_ABM"
            }
            return empty
        }

        let attributes = record.attributes
        let coverage = record.selectedCoverage

        return [
            attributes.deviceModel ?? "",
            attributes.productType ?? "",
            attributes.deviceCapacity ?? "",
            attributes.color ?? "",
            ExportHelpers.isoDate(record.purchaseDate),
            record.purchaseDateSource.exportValue,
            attributes.purchaseSourceType ?? "",
            attributes.orderNumber ?? "",
            coverage?.coverageDescription ?? "",
            ExportHelpers.isoDate(coverage?.startDate),
            ExportHelpers.isoDate(record.warrantyEndDate),
            warrantyStatus(for: record),
            ExportHelpers.isoDate(record.lifecycleDate(years: lifecycleYears)),
            ExportHelpers.isoDate(attributes.addedToOrgDate),
            attributes.status ?? "",
            ExportHelpers.isoDate(record.releasedFromOrgDate)
        ]
    }

    /// Apple's own status where there is one, and distinct tokens for the two cases Apple has no
    /// word for. `NO_RECORD` is a device Apple holds no cover for; `UNAVAILABLE` is one whose
    /// warranty request failed. Reporting the second as the first would turn a fetch problem into a
    /// statement about the hardware.
    private static func warrantyStatus(for record: ABMDeviceRecord) -> String {
        switch record.warrantyState {
        case .active:
            return record.selectedCoverage?.status ?? "ACTIVE"
        case .expired:
            return record.selectedCoverage?.status ?? "INACTIVE"
        case .noRecord:
            return "NO_RECORD"
        case .unavailable:
            return "UNAVAILABLE"
        }
    }

    // MARK: - Async variant

    /// Async variant that resolves Building and Department IDs to names via the Jamf API, and
    /// attaches the cached Apple Business Manager data, before generating the CSV.
    ///
    /// Falls back to the raw IDs if the lookups fail, and omits the ABM columns when no fleet data
    /// has been fetched. Reads the cache rather than the network — an export never triggers 153
    /// warranty requests.
    static func exportToCSV(
        computers: [ComputerInventoryRecord],
        api: JamfAPIService
    ) async -> String {
        async let buildingsCall: [String: String] = {
            (try? await api.fetchBuildings()) ?? [:]
        }()
        async let departmentsCall: [String: String] = {
            (try? await api.fetchDepartments()) ?? [:]
        }()
        let (buildings, departments) = await (buildingsCall, departmentsCall)

        let fleet = ABMFleetStore.shared
        await fleet.loadFromCache()

        let lifecycleYears = UserDefaults.standard.object(forKey: "abmLifecycleYears") as? Int ?? 4

        return exportToCSV(
            computers: computers,
            buildings: buildings,
            departments: departments,
            abmRecords: fleet.recordsBySerial,
            lifecycleYears: lifecycleYears
        )
    }
}
