//
//  PolicyModels.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import Foundation

// MARK: - API List Response
struct PolicyListResponse: Codable {
    let policies: [PolicyListItem]
}

struct PolicyListItem: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Detailed Policy Record
// Used for the Dashboard (Hydrated) and Inspector
struct Policy: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let categoryId: Int?
    let categoryName: String?
    let enabled: Bool
    let scope: PolicyScope?
    
    // Helper for Grouping
    var safeCategory: String { categoryName ?? "No Category" }
}

// MARK: - API Detail Response (Classic API)
struct PolicyDetailResponse: Codable {
    let policy: PolicyDetailXML
}

// Intermediate structure to map Classic API nested JSON
struct PolicyDetailXML: Codable {
    let general: PolicyGeneral
    let scope: PolicyScope
    let package_configuration: PolicyPackageConfiguration?
    let scripts: [PolicyScript]?
    let printers: [PolicyPrinter]?
    let dock_items: [PolicyDockItem]?
    let files_processes: PolicyFilesProcesses?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = try container.decode(PolicyGeneral.self, forKey: .general)
        scope = try container.decode(PolicyScope.self, forKey: .scope)
        files_processes = try container.decodeIfPresent(PolicyFilesProcesses.self, forKey: .files_processes)
        package_configuration = try container.decodeIfPresent(PolicyPackageConfiguration.self, forKey: .package_configuration)
        
        // Handle arrays that might be empty or missing
        scripts = try? container.decode([PolicyScript].self, forKey: .scripts)
        printers = try? container.decode([PolicyPrinter].self, forKey: .printers)
        dock_items = try? container.decode([PolicyDockItem].self, forKey: .dock_items)
    }
    
    enum CodingKeys: String, CodingKey {
        case general, scope, package_configuration, scripts, printers, dock_items, files_processes
    }
}

// MARK: - Policy Package Configuration
struct PolicyPackageConfiguration: Codable {
    let packages: [PolicyPackage]?
    let distribution_point: String?
}

// MARK: - Policy Packages  
struct PolicyPackage: Codable, Identifiable {
    let id: Int
    let name: String
    let action: String?
    let fut: Bool?
    let feu: Bool?
    let update_autorun: Bool?
}

// MARK: - Policy Scripts
struct PolicyScript: Codable, Identifiable {
    let id: String
    let name: String
    let priority: String?
    let parameter4: String?
    let parameter5: String?
    let parameter6: String?
    let parameter7: String?
    let parameter8: String?
    let parameter9: String?
    let parameter10: String?
    let parameter11: String?
}

// MARK: - Policy Printers
struct PolicyPrinter: Codable, Identifiable {
    let id: Int
    let name: String
    let action: String?
    let make_default: Bool?
}

// MARK: - Policy Dock Items
struct PolicyDockItem: Codable, Identifiable {
    let id: Int
    let name: String
    let action: String?
}

// MARK: - Policy Files and Processes
struct PolicyFilesProcesses: Codable {
    let search_by_path: String?
    let delete_file: Bool?
    let locate_file: String?
    let update_locate_database: Bool?
    let spotlight_search: String?
    let search_for_process: String?
    let kill_process: Bool?
    let run_command: String?
}

struct PolicyGeneral: Codable {
    let id: Int
    let name: String
    let enabled: Bool
    let category: PolicyCategory?
    let frequency: String?
    let trigger: String?
    let trigger_checkin: Bool?
    let trigger_enrollment_complete: Bool?
    let trigger_login: Bool?
    let trigger_logout: Bool?
    let trigger_network_state_changed: Bool?
    let trigger_startup: Bool?
    let trigger_other: String?
}

struct PolicyCategory: Codable {
    let id: Int
    let name: String
}

struct PolicyScope: Codable, Hashable {
    let all_computers: Bool
    let computers: [PolicyComputerTarget]?
    let computer_groups: [PolicyComputerTarget]?
    let exclusions: PolicyExclusions?
}

struct PolicyExclusions: Codable, Hashable {
    let computers: [PolicyComputerTarget]?
    let computer_groups: [PolicyComputerTarget]?
}

struct PolicyComputerTarget: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}
