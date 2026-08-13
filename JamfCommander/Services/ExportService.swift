//
//  ExportService.swift
//  JamfCommander
//
//  Main export service coordinator that delegates to specialized export services

import Foundation
import AppKit
import UniformTypeIdentifiers
import UserNotifications

class ExportService {

    // MARK: - Policy Export Delegation

    static func exportPoliciesToCSV(policies: [Policy]) -> String {
        return PolicyExportService.exportToCSV(policies: policies)
    }

    static func exportPoliciesDetailedToCSV(policies: [Policy], api: JamfAPIService, progress: ExportProgress? = nil) async -> String {
        return await PolicyExportService.exportDetailedToCSV(policies: policies, api: api, progress: progress)
    }

    // MARK: - Profile Export Delegation

    static func exportProfilesToCSV(profiles: [ConfigProfile]) -> String {
        return ProfileExportService.exportToCSV(profiles: profiles)
    }

    static func exportProfilesDetailedToCSV(profiles: [ConfigProfile], api: JamfAPIService, progress: ExportProgress? = nil) async -> String {
        return await ProfileExportService.exportDetailedToCSV(profiles: profiles, api: api, progress: progress)
    }

    // MARK: - Script Export Delegation

    static func exportScriptsToCSV(scripts: [ScriptRecord]) -> String {
        return ScriptExportService.exportToCSV(scripts: scripts)
    }

    // MARK: - Computer Export Delegation

    /// Synchronous variant — does not resolve Building/Department IDs to names.
    /// Prefer the async overload below when an API instance is available.
    static func exportComputersToCSV(computers: [ComputerInventoryRecord]) -> String {
        return ComputerExportService.exportToCSV(computers: computers)
    }

    /// Async variant — resolves Building and Department IDs to readable names via the API.
    static func exportComputersToCSV(computers: [ComputerInventoryRecord], api: JamfAPIService) async -> String {
        return await ComputerExportService.exportToCSV(computers: computers, api: api)
    }

    // MARK: - Package Export Delegation

    /// Installomator apps deployed in this tenant. Discovers them through the same path the Packages
    /// module uses, so the export and the screen always agree.
    static func exportPackagesToCSV(api: JamfAPIService, preferredScriptID: String = "") async throws -> String {
        return try await PackageExportService.exportToCSV(api: api, preferredScriptID: preferredScriptID)
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

            // Installomator deployments. A failure here drops one CSV from the archive rather than
            // losing the whole export — detection depends on discovering the tenant's Installomator
            // script, which the other exports do not, and is reported as failed rather than silently
            // producing an archive one file short.
            progress?.updateProgress(for: .packages, status: .fetching)
            let packageCSV: String?
            if let deployedPackages = try? await api.fetchDeployedInstallomatorPolicies() {
                packageCSV = PackageExportService.exportToCSV(policies: deployedPackages)
                progress?.updateProgress(
                    for: .packages,
                    status: .complete,
                    count: deployedPackages.count,
                    total: deployedPackages.count
                )
            } else {
                packageCSV = nil
                progress?.updateProgress(for: .packages, status: .failed)
            }

            // Generate CSVs
            progress?.setCurrentTask("Generating CSV files...")
            let computerCSV = await ComputerExportService.exportToCSV(computers: computerData, api: api)
            let scriptCSV = ScriptExportService.exportToCSV(scripts: scriptData)

            // Generate detailed exports for policies and profiles (with progress updates)
            let policyCSV = await PolicyExportService.exportDetailedToCSV(policies: policyData, api: api, progress: progress)
            let profileCSV = await ProfileExportService.exportDetailedToCSV(profiles: profileData, api: api, progress: progress)

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

            if let packageCSV {
                try packageCSV.write(to: tempDir.appendingPathComponent("Packages_\(dateString).csv"), atomically: true, encoding: .utf8)
            }

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
