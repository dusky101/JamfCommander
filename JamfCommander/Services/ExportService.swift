//
//  ExportService.swift
//  JamfCommander
//
//  Export service for generating CSV/XLSX files from Jamf data

import Foundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

class ExportService {
    
    // MARK: - Policy Export
    
    /// Export policies to CSV format
    /// Includes: ID, Name, Category, Enabled, Scope Type, Target Count
    static func exportPoliciesToCSV(policies: [Policy]) -> String {
        var csv = "ID,Name,Category,Enabled,Scope Type,Target Count\n"
        
        for policy in policies.sorted(by: { $0.name < $1.name }) {
            let id = policy.id
            let name = escapeCSV(policy.name)
            let category = escapeCSV(policy.categoryName ?? "No Category")
            let enabled = policy.enabled ? "Yes" : "No"
            
            // Determine scope type and target count
            var scopeType = "No Scope"
            var targetCount = 0
            
            if let scope = policy.scope {
                if scope.all_computers {
                    scopeType = "All Computers"
                    targetCount = 0 // All computers
                } else if let computers = scope.computers, !computers.isEmpty {
                    scopeType = "Specific Computers"
                    targetCount = computers.count
                } else {
                    scopeType = "No Scope"
                }
            }
            
            csv += "\(id),\(name),\(category),\(enabled),\(scopeType),\(targetCount)\n"
        }
        
        return csv
    }
    
    // MARK: - Profile Export
    
    /// Export configuration profiles to CSV format
    /// Includes: ID, Name, Category, Status (Scoped/Unscoped)
    static func exportProfilesToCSV(profiles: [ConfigProfile]) -> String {
        var csv = "ID,Name,Category,Status\n"
        
        for profile in profiles.sorted(by: { $0.name < $1.name }) {
            let id = profile.id
            let name = escapeCSV(profile.name)
            let category = escapeCSV(profile.categoryName)
            let status = profile.isActive ? "Scoped" : "Unscoped"
            
            csv += "\(id),\(name),\(category),\(status)\n"
        }
        
        return csv
    }
    
    // MARK: - Script Export
    
    /// Export scripts to CSV format
    /// Includes: ID, Name, Category, Priority, OS Requirements, Parameters (4-11)
    static func exportScriptsToCSV(scripts: [ScriptRecord]) -> String {
        var csv = "ID,Name,Category,Priority,OS Requirements,Info,Notes,Parameter 4,Parameter 5,Parameter 6,Parameter 7,Parameter 8,Parameter 9,Parameter 10,Parameter 11\n"
        
        for script in scripts.sorted(by: { $0.name < $1.name }) {
            let id = escapeCSV(script.id)
            let name = escapeCSV(script.name)
            let category = escapeCSV(script.categoryName ?? "Uncategorised")
            let priority = escapeCSV(script.priority ?? "")
            let osReqs = escapeCSV(script.osRequirements ?? "")
            let info = escapeCSV(script.info ?? "")
            let notes = escapeCSV(script.notes ?? "")
            let p4 = escapeCSV(script.parameter4 ?? "")
            let p5 = escapeCSV(script.parameter5 ?? "")
            let p6 = escapeCSV(script.parameter6 ?? "")
            let p7 = escapeCSV(script.parameter7 ?? "")
            let p8 = escapeCSV(script.parameter8 ?? "")
            let p9 = escapeCSV(script.parameter9 ?? "")
            let p10 = escapeCSV(script.parameter10 ?? "")
            let p11 = escapeCSV(script.parameter11 ?? "")
            
            csv += "\(id),\(name),\(category),\(priority),\(osReqs),\(info),\(notes),\(p4),\(p5),\(p6),\(p7),\(p8),\(p9),\(p10),\(p11)\n"
        }
        
        return csv
    }
    
    // MARK: - Computer Export
    
    /// Export computers to CSV format
    /// Includes: ID, Name, Serial Number, Model, IP Address, Last Contact, Managed Status
    static func exportComputersToCSV(computers: [ComputerInventoryRecord]) -> String {
        var csv = "ID,Name,Serial Number,Model,IP Address,Last Contact,Managed,Management Username\n"
        
        for computer in computers.sorted(by: { ($0.general?.name ?? "") < ($1.general?.name ?? "") }) {
            let id = computer.id
            let name = escapeCSV(computer.general?.name ?? "Unknown")
            let serial = escapeCSV(computer.hardware?.serialNumber ?? "N/A")
            let model = escapeCSV(computer.hardware?.model ?? "N/A")
            let ip = escapeCSV(computer.general?.lastIpAddress ?? computer.general?.lastReportedIp ?? "N/A")
            let lastContact = escapeCSV(computer.general?.lastContactTime ?? "N/A")
            let managed = computer.general?.remoteManagement?.managed == true ? "Yes" : "No"
            let managementUser = escapeCSV(computer.general?.remoteManagement?.managementUsername ?? "N/A")
            
            csv += "\(id),\(name),\(serial),\(model),\(ip),\(lastContact),\(managed),\(managementUser)\n"
        }
        
        return csv
    }
    
    // MARK: - Helper Functions
    
    /// Escape CSV fields (handle commas, quotes, newlines)
    private static func escapeCSV(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
    
    // MARK: - Save to File
    
    /// Save CSV content to a file with save panel
    /// Returns true if saved successfully
    @discardableResult
    static func saveCSVToFile(content: String, defaultName: String) -> Bool {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = defaultName
        savePanel.title = "Export to CSV"
        savePanel.message = "Choose a location to save the CSV file"
        
        let response = savePanel.runModal()
        
        if response == .OK, let url = savePanel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                // Show success notification
                showNotification(title: "Export Successful", message: "File saved to \(url.lastPathComponent)")
                return true
            } catch {
                // Show error notification
                showNotification(title: "Export Failed", message: error.localizedDescription)
                return false
            }
        }
        
        return false
    }
    
    /// Show macOS notification
    private static func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
}
