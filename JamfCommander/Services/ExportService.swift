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
    
    /// Export policies to CSV format (Basic version)
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
    
    /// Export policies with detailed information (Async version)
    /// Fetches full policy details including triggers, frequency, scope, etc.
    static func exportPoliciesDetailedToCSV(policies: [Policy], api: JamfAPIService, progress: ExportProgress? = nil) async -> String {
        var csv = "ID,Name,Category,Enabled,Frequency,Triggers,Scoped To,Computer Groups,Target Count,Exclusions\n"
        
        // Fetch details for each policy with rate limiting and retries
        var detailedRows: [(id: Int, row: String)] = []
        
        // Update progress
        progress?.updateProgress(for: .policies, status: .fetching, total: policies.count)
        progress?.setCurrentTask("Fetching policy details...")
        
        // Process in batches of 10 with delays to avoid overwhelming the API
        let batchSize = 10
        let batches = stride(from: 0, to: policies.count, by: batchSize).map {
            Array(policies[$0..<min($0 + batchSize, policies.count)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: (Int, String)?.self) { group in
                for policy in batch {
                    group.addTask {
                        // Retry logic: try up to 3 times with exponential backoff
                        for attempt in 1...3 {
                            do {
                                let detail = try await api.fetchPolicyDetail(id: policy.id)
                                
                                let id = policy.id
                                let name = escapeCSV(detail.general.name)
                                let category = escapeCSV(detail.general.category?.name ?? "No Category")
                                let enabled = detail.general.enabled ? "Yes" : "No"
                                let frequency = escapeCSV(detail.general.frequency ?? "N/A")
                                
                                // Build triggers list
                                var triggers: [String] = []
                                if detail.general.trigger_checkin == true { triggers.append("Check-in") }
                                if detail.general.trigger_enrollment_complete == true { triggers.append("Enrollment Complete") }
                                if detail.general.trigger_login == true { triggers.append("Login") }
                                if detail.general.trigger_logout == true { triggers.append("Logout") }
                                if detail.general.trigger_network_state_changed == true { triggers.append("Network State Changed") }
                                if detail.general.trigger_startup == true { triggers.append("Startup") }
                                if let other = detail.general.trigger_other, !other.isEmpty { triggers.append(other) }
                                if let mainTrigger = detail.general.trigger, !mainTrigger.isEmpty { triggers.append(mainTrigger) }
                                let triggersList = triggers.isEmpty ? "None" : triggers.joined(separator: "; ")
                                
                                // Scope information
                                var scopedTo = "None"
                                var computerGroups = ""
                                var targetCount = 0
                                
                                if detail.scope.all_computers {
                                    scopedTo = "All Computers"
                                } else if let groups = detail.scope.computer_groups, !groups.isEmpty {
                                    scopedTo = "Computer Groups"
                                    computerGroups = groups.map { $0.name }.joined(separator: "; ")
                                    targetCount = groups.count
                                } else if let computers = detail.scope.computers, !computers.isEmpty {
                                    scopedTo = "Specific Computers"
                                    targetCount = computers.count
                                }
                                
                                // Exclusions
                                var exclusionsList = ""
                                if let exclusions = detail.scope.exclusions {
                                    var parts: [String] = []
                                    if let exGroups = exclusions.computer_groups, !exGroups.isEmpty {
                                        parts.append("Groups: \(exGroups.map { $0.name }.joined(separator: ", "))")
                                    }
                                    if let exComputers = exclusions.computers, !exComputers.isEmpty {
                                        parts.append("Computers: \(exComputers.count)")
                                    }
                                    exclusionsList = parts.joined(separator: "; ")
                                }
                                
                                let row = "\(id),\(name),\(category),\(enabled),\(frequency),\(escapeCSV(triggersList)),\(escapeCSV(scopedTo)),\(escapeCSV(computerGroups)),\(targetCount),\(escapeCSV(exclusionsList))\n"
                                
                                return (id, row)
                            } catch {
                                if attempt == 3 {
                                    print("Failed to hydrate policy \(policy.id) after 3 attempts: \(error)")
                                    return nil
                                }
                                // Wait with exponential backoff: 0.5s, 1s, 2s
                                try? await Task.sleep(nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000))
                            }
                        }
                        return nil
                    }
                }
                
                for await result in group {
                    if let (id, row) = result {
                        detailedRows.append((id, row))
                        progress?.updateProgress(for: .policies, status: .processing(current: detailedRows.count, total: policies.count), count: detailedRows.count, total: policies.count)
                    }
                }
            }
            
            // Add delay between batches (except for last batch)
            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay between batches
            }
        }
        
        progress?.updateProgress(for: .policies, status: .complete, count: detailedRows.count, total: policies.count)
        
        // Sort by ID and build final CSV
        for (_, row) in detailedRows.sorted(by: { $0.id < $1.id }) {
            csv += row
        }
        
        return csv
    }
    
    // MARK: - Profile Export
    
    /// Export configuration profiles to CSV format (Basic version)
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
    
    /// Export configuration profiles with detailed information (Async version)
    /// Fetches full profile details including scope, distribution method, etc.
    static func exportProfilesDetailedToCSV(profiles: [ConfigProfile], api: JamfAPIService, progress: ExportProgress? = nil) async -> String {
        var csv = "ID,Name,Category,Status,Distribution Method,Level,User Removable,Redeploy on Update,Scoped To,Computer Groups,Exclusions\n"
        
        // Fetch details for each profile with rate limiting and retries
        var detailedRows: [(id: Int, row: String)] = []
        
        // Update progress
        progress?.updateProgress(for: .profiles, status: .fetching, total: profiles.count)
        progress?.setCurrentTask("Fetching profile details...")
        
        // Process in batches of 10 with delays to avoid overwhelming the API
        let batchSize = 10
        let batches = stride(from: 0, to: profiles.count, by: batchSize).map {
            Array(profiles[$0..<min($0 + batchSize, profiles.count)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: (Int, String)?.self) { group in
                for profile in batch {
                    group.addTask {
                        // Retry logic: try up to 3 times with exponential backoff
                        for attempt in 1...3 {
                            do {
                                let detail = try await api.fetchProfileScope(id: profile.id)
                                
                                let id = profile.id
                                let name = escapeCSV(profile.name)
                                let category = escapeCSV(profile.categoryName)
                                let status = profile.isActive ? "Scoped" : "Unscoped"
                                let distributionMethod = escapeCSV(detail.general.distribution_method ?? "N/A")
                                let level = escapeCSV(detail.general.level ?? "N/A")
                                let userRemovable = (detail.general.user_removable ?? false) ? "Yes" : "No"
                                let redeployOnUpdate = escapeCSV(detail.general.redeploy_on_update ?? "N/A")
                                
                                // Scope information
                                var scopedTo = "None"
                                var computerGroups = ""
                                
                                if detail.scope.all_computers {
                                    scopedTo = "All Computers"
                                } else if let groups = detail.scope.computer_groups, !groups.isEmpty {
                                    scopedTo = "Computer Groups"
                                    computerGroups = groups.map { $0.name }.joined(separator: "; ")
                                } else if let computers = detail.scope.computers, !computers.isEmpty {
                                    scopedTo = "Specific Computers (\(computers.count))"
                                }
                                
                                // Exclusions
                                var exclusionsList = ""
                                if let exclusions = detail.scope.exclusions {
                                    var parts: [String] = []
                                    if let exGroups = exclusions.computer_groups, !exGroups.isEmpty {
                                        parts.append("Groups: \(exGroups.map { $0.name }.joined(separator: ", "))")
                                    }
                                    if let exComputers = exclusions.computers, !exComputers.isEmpty {
                                        parts.append("Computers: \(exComputers.count)")
                                    }
                                    exclusionsList = parts.joined(separator: "; ")
                                }
                                
                                let row = "\(id),\(name),\(category),\(status),\(distributionMethod),\(level),\(userRemovable),\(redeployOnUpdate),\(escapeCSV(scopedTo)),\(escapeCSV(computerGroups)),\(escapeCSV(exclusionsList))\n"
                                
                                return (id, row)
                            } catch {
                                if attempt == 3 {
                                    print("Failed to fetch details for profile \(profile.id) after 3 attempts: \(error)")
                                    return nil
                                }
                                // Wait with exponential backoff: 0.5s, 1s, 2s
                                try? await Task.sleep(nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000))
                            }
                        }
                        return nil
                    }
                }
                
                for await result in group {
                    if let (id, row) = result {
                        detailedRows.append((id, row))
                        progress?.updateProgress(for: .profiles, status: .processing(current: detailedRows.count, total: profiles.count), count: detailedRows.count, total: profiles.count)
                    }
                }
            }
            
            // Add delay between batches (except for last batch)
            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay between batches
            }
        }
        
        progress?.updateProgress(for: .profiles, status: .complete, count: detailedRows.count, total: profiles.count)
        
        // Sort by ID and build final CSV
        for (_, row) in detailedRows.sorted(by: { $0.id < $1.id }) {
            csv += row
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
    nonisolated private static func escapeCSV(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
    
    // MARK: - Export All Data
    
    /// Export all data types to a single ZIP file containing separate CSVs
    static func exportAllDataToZip(api: JamfAPIService, progress: ExportProgress? = nil) async -> Bool {
        do {
            // Fetch all data in parallel
            progress?.setCurrentTask("Fetching data from Jamf...")
            
            progress?.updateProgress(for: .computers, status: .fetching)
            let computerData = try await api.fetchComputers()
            progress?.updateProgress(for: .computers, status: .complete, count: computerData.count, total: computerData.count)
            
            progress?.updateProgress(for: .scripts, status: .fetching)
            let scriptData = try await api.fetchScripts()
            progress?.updateProgress(for: .scripts, status: .complete, count: scriptData.count, total: scriptData.count)
            
            let policyData = try await api.fetchPolicies()
            let profileData = try await api.fetchProfiles()
            
            // Generate CSVs
            progress?.setCurrentTask("Generating CSV files...")
            let computerCSV = exportComputersToCSV(computers: computerData)
            let scriptCSV = exportScriptsToCSV(scripts: scriptData)
            
            // Generate detailed exports for policies and profiles (with progress updates)
            let policyCSV = await exportPoliciesDetailedToCSV(policies: policyData, api: api, progress: progress)
            let profileCSV = await exportProfilesDetailedToCSV(profiles: profileData, api: api, progress: progress)
            
            // Create temporary directory for CSV files
            progress?.setCurrentTask("Creating archive...")
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Write CSV files
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = dateFormatter.string(from: Date())
            
            try computerCSV.write(to: tempDir.appendingPathComponent("Computers_\(dateString).csv"), atomically: true, encoding: .utf8)
            try policyCSV.write(to: tempDir.appendingPathComponent("Policies_\(dateString).csv"), atomically: true, encoding: .utf8)
            try profileCSV.write(to: tempDir.appendingPathComponent("Profiles_\(dateString).csv"), atomically: true, encoding: .utf8)
            try scriptCSV.write(to: tempDir.appendingPathComponent("Scripts_\(dateString).csv"), atomically: true, encoding: .utf8)
            
            // Create ZIP archive
            let zipURL = tempDir.appendingPathComponent("JamfCommander_Export_\(dateString).zip")
            try await createZipArchive(from: tempDir, to: zipURL)
            
            progress?.markComplete()
            
            // Present save panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.zip]
            savePanel.nameFieldStringValue = "JamfCommander_Export_\(dateString).zip"
            savePanel.title = "Export All Data"
            savePanel.message = "Save complete Jamf data export"
            
            let response = await MainActor.run { savePanel.runModal() }
            
            if response == .OK, let destination = savePanel.url {
                // Copy ZIP to destination
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zipURL, to: destination)
                
                // Clean up temp directory
                try? FileManager.default.removeItem(at: tempDir)
                
                // Show success notification
                showNotification(title: "Export Successful", message: "All data exported to \(destination.lastPathComponent)")
                return true
            }
            
            // Clean up if cancelled
            try? FileManager.default.removeItem(at: tempDir)
            return false
            
        } catch {
            print("Export all failed: \(error)")
            showNotification(title: "Export Failed", message: error.localizedDescription)
            return false
        }
    }
    
    /// Create a ZIP archive from a directory
    private static func createZipArchive(from sourceDir: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        
        // Use the system's zip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-q", destinationURL.path] + files.map { $0.path }
        process.currentDirectoryURL = sourceDir
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ExportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
        }
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
