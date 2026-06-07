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
    let self_service: PolicySelfServiceXML?
    let package_configuration: PolicyPackageConfiguration?
    let scripts: [PolicyScript]?
    let printers: [PolicyPrinter]?
    let dock_items: [PolicyDockItem]?
    let files_processes: PolicyFilesProcesses?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = try container.decode(PolicyGeneral.self, forKey: .general)
        scope = try container.decode(PolicyScope.self, forKey: .scope)
        // Self Service is optional and its shape varies; never let it break the
        // existing decode (list hydration / inspector). Degrade to nil on any problem.
        self_service = try? container.decode(PolicySelfServiceXML.self, forKey: .self_service)
        files_processes = try container.decodeIfPresent(PolicyFilesProcesses.self, forKey: .files_processes)
        package_configuration = try container.decodeIfPresent(PolicyPackageConfiguration.self, forKey: .package_configuration)

        // Handle arrays that might be empty or missing
        scripts = try? container.decode([PolicyScript].self, forKey: .scripts)
        printers = try? container.decode([PolicyPrinter].self, forKey: .printers)
        dock_items = try? container.decode([PolicyDockItem].self, forKey: .dock_items)
    }

    enum CodingKeys: String, CodingKey {
        case general, scope, self_service, package_configuration, scripts, printers, dock_items, files_processes
    }
}

// MARK: - Policy Self Service (Classic API decode layer)
// Mirrors the `self_service` object on GET /JSSResource/policies/id/{id}. All fields
// are optional and decoded defensively so a shape change can never throw and break the
// surrounding policy decode (see models-and-decoding.md). The clean, UI-facing value type
// is `SelfServiceSettings` in PolicyEditingModels.swift.
struct PolicySelfServiceXML: Codable {
    let use_for_self_service: Bool?
    let self_service_display_name: String?
    let install_button_text: String?
    let reinstall_button_text: String?
    let self_service_description: String?
    let force_users_to_view_description: Bool?
    let feature_on_main_page: Bool?
    let self_service_icon: PolicySelfServiceIconXML?
    let self_service_categories: [PolicySelfServiceCategoryXML]?

    enum CodingKeys: String, CodingKey {
        case use_for_self_service
        case self_service_display_name
        case install_button_text
        case reinstall_button_text
        case self_service_description
        case force_users_to_view_description
        case feature_on_main_page
        case self_service_icon
        case self_service_categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        use_for_self_service = try? c.decode(Bool.self, forKey: .use_for_self_service)
        self_service_display_name = try? c.decode(String.self, forKey: .self_service_display_name)
        install_button_text = try? c.decode(String.self, forKey: .install_button_text)
        reinstall_button_text = try? c.decode(String.self, forKey: .reinstall_button_text)
        self_service_description = try? c.decode(String.self, forKey: .self_service_description)
        force_users_to_view_description = try? c.decode(Bool.self, forKey: .force_users_to_view_description)
        feature_on_main_page = try? c.decode(Bool.self, forKey: .feature_on_main_page)
        self_service_icon = try? c.decode(PolicySelfServiceIconXML.self, forKey: .self_service_icon)
        self_service_categories = PolicySelfServiceXML.decodeCategories(from: c)
    }

    /// Tolerates the categories arriving either as a bare array (Jamf's usual Classic-JSON
    /// flattening of `<self_service_categories><category>…`) or wrapped in a
    /// `{ "category": … }` object holding an array or a single object, so a shape change
    /// doesn't silently drop the categories.
    private static func decodeCategories(from c: KeyedDecodingContainer<CodingKeys>) -> [PolicySelfServiceCategoryXML]? {
        if let array = try? c.decode([PolicySelfServiceCategoryXML].self, forKey: .self_service_categories) {
            return array
        }
        if let wrapper = try? c.decode(SelfServiceCategoriesWrapper.self, forKey: .self_service_categories) {
            return wrapper.category
        }
        return nil
    }

    private struct SelfServiceCategoriesWrapper: Codable {
        let category: [PolicySelfServiceCategoryXML]?

        enum CodingKeys: String, CodingKey { case category }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let array = try? c.decode([PolicySelfServiceCategoryXML].self, forKey: .category) {
                category = array
            } else if let single = try? c.decode(PolicySelfServiceCategoryXML.self, forKey: .category) {
                category = [single]
            } else {
                category = nil
            }
        }
    }
}

struct PolicySelfServiceCategoryXML: Codable {
    let id: Int?
    let name: String?
    let display_in: Bool?
    let feature_in: Bool?

    enum CodingKeys: String, CodingKey { case id, name, display_in, feature_in }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Jamf may return the id as an Int or a String depending on the API path.
        if let intID = try? c.decode(Int.self, forKey: .id) {
            id = intID
        } else if let strID = try? c.decode(String.self, forKey: .id) {
            id = Int(strID)
        } else {
            id = nil
        }
        name = try? c.decode(String.self, forKey: .name)
        display_in = try? c.decode(Bool.self, forKey: .display_in)
        feature_in = try? c.decode(Bool.self, forKey: .feature_in)
    }
}

struct PolicySelfServiceIconXML: Codable {
    let id: Int?
    let filename: String?
    let uri: String?

    enum CodingKeys: String, CodingKey { case id, filename, uri }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? c.decode(Int.self, forKey: .id) {
            id = intID
        } else if let strID = try? c.decode(String.self, forKey: .id) {
            id = Int(strID)
        } else {
            id = nil
        }
        filename = try? c.decode(String.self, forKey: .filename)
        uri = try? c.decode(String.self, forKey: .uri)
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
    
    // Jamf Classic API returns script id as Int, but we store as String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle id being either Int or String
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        
        name = try container.decode(String.self, forKey: .name)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        parameter4 = try container.decodeIfPresent(String.self, forKey: .parameter4)
        parameter5 = try container.decodeIfPresent(String.self, forKey: .parameter5)
        parameter6 = try container.decodeIfPresent(String.self, forKey: .parameter6)
        parameter7 = try container.decodeIfPresent(String.self, forKey: .parameter7)
        parameter8 = try container.decodeIfPresent(String.self, forKey: .parameter8)
        parameter9 = try container.decodeIfPresent(String.self, forKey: .parameter9)
        parameter10 = try container.decodeIfPresent(String.self, forKey: .parameter10)
        parameter11 = try container.decodeIfPresent(String.self, forKey: .parameter11)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, priority
        case parameter4, parameter5, parameter6, parameter7
        case parameter8, parameter9, parameter10, parameter11
    }
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
