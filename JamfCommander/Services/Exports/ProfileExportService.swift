//
//  ProfileExportService.swift
//  JamfCommander
//
//  Profile export functionality

import Foundation

class ProfileExportService {

    /// Export configuration profiles to CSV format (Basic version)
    /// Includes: ID, Name, Category, Status (Scoped/Unscoped)
    static func exportToCSV(profiles: [ConfigProfile]) -> String {
        var csv = "ID,Name,Category,Status\n"

        for profile in profiles.sorted(by: { $0.name < $1.name }) {
            let id = profile.id
            let name = ExportHelpers.escapeCSV(profile.name)
            let category = ExportHelpers.escapeCSV(profile.categoryName)
            let status = profile.isActive ? "Scoped" : "Unscoped"

            csv += "\(id),\(name),\(category),\(status)\n"
        }

        return csv
    }

    /// Export configuration profiles with detailed information (Async version)
    /// Fetches full profile details including scope, distribution method, etc.
    static func exportDetailedToCSV(profiles: [ConfigProfile], api: JamfAPIService, progress: ExportProgress? = nil) async -> String {
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
                                let name = ExportHelpers.escapeCSV(profile.name)
                                let category = ExportHelpers.escapeCSV(profile.categoryName)
                                let status = profile.isActive ? "Scoped" : "Unscoped"
                                let distributionMethod = ExportHelpers.escapeCSV(detail.general.distribution_method ?? "N/A")
                                let level = ExportHelpers.escapeCSV(detail.general.level ?? "N/A")
                                let userRemovable = (detail.general.user_removable ?? false) ? "Yes" : "No"
                                let redeployOnUpdate = ExportHelpers.escapeCSV(detail.general.redeploy_on_update ?? "N/A")

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

                                let row = "\(id),\(name),\(category),\(status),\(distributionMethod),\(level),\(userRemovable),\(redeployOnUpdate),\(ExportHelpers.escapeCSV(scopedTo)),\(ExportHelpers.escapeCSV(computerGroups)),\(ExportHelpers.escapeCSV(exclusionsList))\n"

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
}
