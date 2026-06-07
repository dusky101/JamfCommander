//
//  ComputerExportService.swift
//  JamfCommander
//
//  Computer export functionality

import Foundation

class ComputerExportService {

    /// Export computers to CSV format.
    /// Includes hardware/management columns plus User & Location columns. Department and
    /// Building IDs are resolved to names when the lookup dictionaries are supplied.
    static func exportToCSV(
        computers: [ComputerInventoryRecord],
        buildings: [String: String] = [:],
        departments: [String: String] = [:]
    ) -> String {
        var csv = "ID,Name,Serial Number,Model,IP Address,Last Contact,Managed,Management Username,Username,Real Name,Email,Position,Phone,Department,Building,Room\n"

        for computer in computers.sorted(by: { ($0.general?.name ?? "") < ($1.general?.name ?? "") }) {
            let id = computer.id
            let name = ExportHelpers.escapeCSV(computer.general?.name ?? "Unknown")
            let serial = ExportHelpers.escapeCSV(computer.hardware?.serialNumber ?? "N/A")
            let model = ExportHelpers.escapeCSV(computer.hardware?.model ?? "N/A")
            let ip = ExportHelpers.escapeCSV(computer.general?.lastIpAddress ?? computer.general?.lastReportedIp ?? "N/A")
            let lastContact = ExportHelpers.escapeCSV(computer.general?.lastContactTime ?? "N/A")
            let managed = computer.general?.remoteManagement?.managed == true ? "Yes" : "No"
            let managementUser = ExportHelpers.escapeCSV(computer.general?.remoteManagement?.managementUsername ?? "N/A")

            let user = computer.userAndLocation
            let username = ExportHelpers.escapeCSV(user?.username ?? "")
            let realname = ExportHelpers.escapeCSV(user?.realname ?? "")
            let email = ExportHelpers.escapeCSV(user?.email ?? "")
            let position = ExportHelpers.escapeCSV(user?.position ?? "")
            let phone = ExportHelpers.escapeCSV(user?.phone ?? "")

            let departmentName: String = {
                guard let depId = user?.departmentId, !depId.isEmpty else { return "" }
                return departments[depId] ?? depId
            }()
            let buildingName: String = {
                guard let bldId = user?.buildingId, !bldId.isEmpty else { return "" }
                return buildings[bldId] ?? bldId
            }()
            let department = ExportHelpers.escapeCSV(departmentName)
            let building = ExportHelpers.escapeCSV(buildingName)
            let room = ExportHelpers.escapeCSV(user?.room ?? "")

            csv += "\(id),\(name),\(serial),\(model),\(ip),\(lastContact),\(managed),\(managementUser),\(username),\(realname),\(email),\(position),\(phone),\(department),\(building),\(room)\n"
        }

        return csv
    }

    /// Async variant that resolves Building and Department IDs to names via the Jamf API
    /// before generating the CSV. Falls back to the raw IDs if the lookups fail.
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
        return exportToCSV(computers: computers, buildings: buildings, departments: departments)
    }
}
