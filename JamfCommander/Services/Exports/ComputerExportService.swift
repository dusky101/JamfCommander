//
//  ComputerExportService.swift
//  JamfCommander
//
//  Computer export functionality

import Foundation

class ComputerExportService {

    /// Export computers to CSV format
    /// Includes: ID, Name, Serial Number, Model, IP Address, Last Contact, Managed Status
    static func exportToCSV(computers: [ComputerInventoryRecord]) -> String {
        var csv = "ID,Name,Serial Number,Model,IP Address,Last Contact,Managed,Management Username\n"

        for computer in computers.sorted(by: { ($0.general?.name ?? "") < ($1.general?.name ?? "") }) {
            let id = computer.id
            let name = ExportHelpers.escapeCSV(computer.general?.name ?? "Unknown")
            let serial = ExportHelpers.escapeCSV(computer.hardware?.serialNumber ?? "N/A")
            let model = ExportHelpers.escapeCSV(computer.hardware?.model ?? "N/A")
            let ip = ExportHelpers.escapeCSV(computer.general?.lastIpAddress ?? computer.general?.lastReportedIp ?? "N/A")
            let lastContact = ExportHelpers.escapeCSV(computer.general?.lastContactTime ?? "N/A")
            let managed = computer.general?.remoteManagement?.managed == true ? "Yes" : "No"
            let managementUser = ExportHelpers.escapeCSV(computer.general?.remoteManagement?.managementUsername ?? "N/A")

            csv += "\(id),\(name),\(serial),\(model),\(ip),\(lastContact),\(managed),\(managementUser)\n"
        }

        return csv
    }
}
