//
//  PolicyExportService.swift
//  JamfCommander
//
//  Policy export functionality

import Foundation

class PolicyExportService {

    /// Export policies to CSV format (Basic version)
    /// Includes: ID, Name, Category, Enabled, Scope Type, Target Count
    static func exportToCSV(policies: [Policy]) -> String {
        var csv = "ID,Name,Category,Enabled,Scope Type,Target Count\n"

        for policy in policies.sorted(by: { $0.name < $1.name }) {
            let id = policy.id
            let name = ExportHelpers.escapeCSV(policy.name)
            let category = ExportHelpers.escapeCSV(policy.categoryName ?? "No Category")
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
    /// Fetches full policy details as raw JSON and dynamically extracts all fields
    static func exportDetailedToCSV(policies: [Policy], api: JamfAPIService, progress: ExportProgress? = nil) async -> String {
        // First, collect all policy JSON data
        var policyDataList: [(id: Int, json: [String: Any])] = []

        progress?.updateProgress(for: .policies, status: .fetching, total: policies.count)
        progress?.setCurrentTask("Fetching policy details...")

        // Process in batches of 10 with delays
        let batchSize = 10
        let batches = stride(from: 0, to: policies.count, by: batchSize).map {
            Array(policies[$0..<min($0 + batchSize, policies.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: (Int, [String: Any])?.self) { group in
                for policy in batch {
                    group.addTask {
                        for attempt in 1...3 {
                            do {
                                let jsonString = try await api.fetchPolicyJSON(id: policy.id)
                                if let data = jsonString.data(using: .utf8),
                                   let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let policyDict = jsonObject["policy"] as? [String: Any] {
                                    return (policy.id, policyDict)
                                }
                                return nil
                            } catch {
                                if attempt == 3 {
                                    print("Failed to fetch policy \(policy.id) after 3 attempts: \(error)")
                                    return nil
                                }
                                try? await Task.sleep(nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000))
                            }
                        }
                        return nil
                    }
                }

                for await result in group {
                    if let (id, json) = result {
                        policyDataList.append((id, json))
                        progress?.updateProgress(for: .policies, status: .processing(current: policyDataList.count, total: policies.count), count: policyDataList.count, total: policies.count)
                    }
                }
            }

            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        progress?.updateProgress(for: .policies, status: .complete, count: policyDataList.count, total: policies.count)

        // Sort by ID
        policyDataList.sort { $0.id < $1.id }

        // Determine which optional columns have data
        var hasPackages = false
        var hasScripts = false
        var hasPrinters = false
        var hasDockItems = false
        var hasFilesProcesses = false

        for (_, policyDict) in policyDataList {
            if let pkgConfig = policyDict["package_configuration"] as? [String: Any],
               let packages = pkgConfig["packages"] as? [[String: Any]], !packages.isEmpty {
                hasPackages = true
            }
            if let scripts = policyDict["scripts"] as? [[String: Any]], !scripts.isEmpty {
                hasScripts = true
            }
            if let printers = policyDict["printers"] as? [[String: Any]], !printers.isEmpty {
                hasPrinters = true
            }
            if let dockItems = policyDict["dock_items"] as? [[String: Any]], !dockItems.isEmpty {
                hasDockItems = true
            }
            if let fp = policyDict["files_processes"] as? [String: Any] {
                if let cmd = fp["run_command"] as? String, !cmd.isEmpty {
                    hasFilesProcesses = true
                } else if let search = fp["search_for_process"] as? String, !search.isEmpty {
                    hasFilesProcesses = true
                } else if let locate = fp["locate_file"] as? String, !locate.isEmpty {
                    hasFilesProcesses = true
                } else if let path = fp["search_by_path"] as? String, !path.isEmpty {
                    hasFilesProcesses = true
                }
            }
        }

        // Build header dynamically
        var headers = ["ID", "Name", "Category", "Enabled", "Frequency", "Triggers", "Scoped To", "Computer Groups", "Target Count", "Exclusions"]
        if hasPackages { headers.append("Packages") }
        if hasScripts { headers.append("Scripts") }
        if hasPrinters { headers.append("Printers") }
        if hasDockItems { headers.append("Dock Items") }
        if hasFilesProcesses { headers.append("Files/Processes") }

        var csv = headers.joined(separator: ",") + "\n"

        // Build rows
        for (id, policyDict) in policyDataList {
            guard let general = policyDict["general"] as? [String: Any],
                  let scope = policyDict["scope"] as? [String: Any] else {
                continue
            }

            let name = ExportHelpers.escapeCSV((general["name"] as? String) ?? "")
            let category = ExportHelpers.escapeCSV(((general["category"] as? [String: Any])?["name"] as? String) ?? "No Category")
            let enabled = (general["enabled"] as? Bool) == true ? "Yes" : "No"
            let frequency = ExportHelpers.escapeCSV((general["frequency"] as? String) ?? "N/A")

            // Triggers
            var triggers: [String] = []
            if (general["trigger_checkin"] as? Bool) == true { triggers.append("Check-in") }
            if (general["trigger_enrollment_complete"] as? Bool) == true { triggers.append("Enrollment Complete") }
            if (general["trigger_login"] as? Bool) == true { triggers.append("Login") }
            if (general["trigger_logout"] as? Bool) == true { triggers.append("Logout") }
            if (general["trigger_network_state_changed"] as? Bool) == true { triggers.append("Network State Changed") }
            if (general["trigger_startup"] as? Bool) == true { triggers.append("Startup") }
            if let other = general["trigger_other"] as? String, !other.isEmpty { triggers.append(other) }
            if let mainTrigger = general["trigger"] as? String, !mainTrigger.isEmpty { triggers.append(mainTrigger) }
            let triggersList = ExportHelpers.escapeCSV(triggers.isEmpty ? "None" : triggers.joined(separator: "; "))

            // Scope
            var scopedTo = "None"
            var computerGroups = ""
            var targetCount = 0

            if (scope["all_computers"] as? Bool) == true {
                scopedTo = "All Computers"
            } else if let groups = scope["computer_groups"] as? [[String: Any]], !groups.isEmpty {
                scopedTo = "Computer Groups"
                computerGroups = groups.compactMap { $0["name"] as? String }.joined(separator: "; ")
                targetCount = groups.count
            } else if let computers = scope["computers"] as? [[String: Any]], !computers.isEmpty {
                scopedTo = "Specific Computers"
                targetCount = computers.count
            }

            // Exclusions
            var exclusionsList = ""
            if let exclusions = scope["exclusions"] as? [String: Any] {
                var parts: [String] = []
                if let exGroups = exclusions["computer_groups"] as? [[String: Any]], !exGroups.isEmpty {
                    let groupNames = exGroups.compactMap { $0["name"] as? String }.joined(separator: ", ")
                    parts.append("Groups: \(groupNames)")
                }
                if let exComputers = exclusions["computers"] as? [[String: Any]], !exComputers.isEmpty {
                    parts.append("Computers: \(exComputers.count)")
                }
                exclusionsList = parts.joined(separator: "; ")
            }

            var row = "\(id),\(name),\(category),\(enabled),\(frequency),\(triggersList),\(ExportHelpers.escapeCSV(scopedTo)),\(ExportHelpers.escapeCSV(computerGroups)),\(targetCount),\(ExportHelpers.escapeCSV(exclusionsList))"

            // Packages
            if hasPackages {
                var packagesList = ""
                if let pkgConfig = policyDict["package_configuration"] as? [String: Any],
                   let packages = pkgConfig["packages"] as? [[String: Any]], !packages.isEmpty {
                    packagesList = packages.compactMap { pkg in
                        guard let name = pkg["name"] as? String else { return nil }
                        var parts = [name]
                        if let action = pkg["action"] as? String {
                            parts.append("(\(action))")
                        }
                        return parts.joined(separator: " ")
                    }.joined(separator: "; ")
                }
                row += ",\(ExportHelpers.escapeCSV(packagesList))"
            }

            // Scripts
            if hasScripts {
                var scriptsList = ""
                if let scripts = policyDict["scripts"] as? [[String: Any]], !scripts.isEmpty {
                    scriptsList = scripts.compactMap { script in
                        guard let name = script["name"] as? String else { return nil }
                        var parts = [name]
                        if let priority = script["priority"] as? String {
                            parts.append("[\(priority)]")
                        }
                        return parts.joined(separator: " ")
                    }.joined(separator: "; ")
                }
                row += ",\(ExportHelpers.escapeCSV(scriptsList))"
            }

            // Printers
            if hasPrinters {
                var printersList = ""
                if let printers = policyDict["printers"] as? [[String: Any]], !printers.isEmpty {
                    printersList = printers.compactMap { printer in
                        guard let name = printer["name"] as? String else { return nil }
                        var parts = [name]
                        if let action = printer["action"] as? String {
                            parts.append("(\(action))")
                        }
                        if (printer["make_default"] as? Bool) == true {
                            parts.append("[Default]")
                        }
                        return parts.joined(separator: " ")
                    }.joined(separator: "; ")
                }
                row += ",\(ExportHelpers.escapeCSV(printersList))"
            }

            // Dock Items
            if hasDockItems {
                var dockItemsList = ""
                if let dockItems = policyDict["dock_items"] as? [[String: Any]], !dockItems.isEmpty {
                    dockItemsList = dockItems.compactMap { item in
                        guard let name = item["name"] as? String else { return nil }
                        var parts = [name]
                        if let action = item["action"] as? String {
                            parts.append("(\(action))")
                        }
                        return parts.joined(separator: " ")
                    }.joined(separator: "; ")
                }
                row += ",\(ExportHelpers.escapeCSV(dockItemsList))"
            }

            // Files and Processes
            if hasFilesProcesses {
                var filesProcessesList = ""
                if let fp = policyDict["files_processes"] as? [String: Any] {
                    var parts: [String] = []
                    if let cmd = fp["run_command"] as? String, !cmd.isEmpty {
                        parts.append("Run: \(cmd)")
                    }
                    if let search = fp["search_for_process"] as? String, !search.isEmpty {
                        parts.append("Search: \(search)")
                        if (fp["kill_process"] as? Bool) == true {
                            parts.append("(Kill)")
                        }
                    }
                    if let locate = fp["locate_file"] as? String, !locate.isEmpty {
                        parts.append("Locate: \(locate)")
                    }
                    if let searchPath = fp["search_by_path"] as? String, !searchPath.isEmpty {
                        parts.append("Path: \(searchPath)")
                        if (fp["delete_file"] as? Bool) == true {
                            parts.append("(Delete)")
                        }
                    }
                    filesProcessesList = parts.joined(separator: "; ")
                }
                row += ",\(ExportHelpers.escapeCSV(filesProcessesList))"
            }

            csv += row + "\n"
        }

        return csv
    }
}
