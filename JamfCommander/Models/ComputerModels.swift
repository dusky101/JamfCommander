//
//  ComputerModels.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import Foundation

// MARK: - Pro API List Response
struct JamfProComputerListResponse: Codable {
    let totalCount: Int
    let results: [ComputerInventoryRecord]
}

// MARK: - Shared Record (Used for List & Detail)
struct ComputerInventoryRecord: Identifiable, Codable, Hashable {
    let id: String
    let general: ComputerGeneral?
    let hardware: ComputerHardware?
    let operatingSystem: ComputerOS?
    let configurationProfiles: [ComputerProfile]?
    let userAndLocation: ComputerUserAndLocation?
    
    // Helper to Convert String ID to Int (for compatibility with UI)
    var intId: Int { Int(id) ?? 0 }
}

// MARK: - Sections

struct ComputerGeneral: Codable, Hashable {
    let name: String
    let lastIpAddress: String?
    let lastReportedIp: String?
    let lastContactTime: String?
    let lastLoggedInUsernameBinary: String?
    let remoteManagement: RemoteManagement?
    
    struct RemoteManagement: Codable, Hashable {
        let managed: Bool
        let managementUsername: String?
    }
}

struct ComputerHardware: Codable, Hashable {
    let model: String?
    let serialNumber: String?
    let processorType: String?
    let processorSpeedMhz: Int? // API sometimes returns Int or String, safe to optional
    let totalRamMegabytes: Int?
}

struct ComputerOS: Codable, Hashable {
    let name: String?
    let version: String?
    let build: String?
    let fileVault2Status: String? // "All Partitions Encrypted", etc.
}

struct ComputerUserAndLocation: Codable, Hashable {
    let username: String?
    let realname: String?
    let email: String?
    let position: String?
    let phone: String?
    let departmentId: String?
    let buildingId: String?
    let room: String?
}

// MARK: - Derived Display Values

/// Trims only to decide whether a value is present, returning it unchanged. Jamf returns `""`
/// as readily as omitting a field, and the two must mean the same thing everywhere.
private func presentValue(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return value
}

/// The single source of truth for how a computer is presented and searched.
///
/// The realname → username fallback used to be written three different ways inside
/// `ComputersDashboardView` alone — the search predicate, the User cell and the sort key — which
/// is exactly how they drifted apart. Views read these; they do not re-derive them.
extension ComputerInventoryRecord {

    /// The computer's name with a readable fallback. Deliberately different from `sortName`, which
    /// falls back to an empty string so an unnamed record sorts first rather than under "U".
    var displayName: String {
        presentValue(general?.name) ?? "Unknown Device"
    }

    /// Whose machine this is: the assigned full name, then the assigned username, then the last
    /// user to log in on the device. `nil` when Jamf knows of nobody.
    var assignedUserDisplayName: String? {
        presentValue(userAndLocation?.realname)
            ?? presentValue(userAndLocation?.username)
            ?? presentValue(general?.lastLoggedInUsernameBinary)
    }

    /// The assigned user's email address, or `nil` when absent or blank.
    var assignedUserEmail: String? {
        presentValue(userAndLocation?.email)
    }

    /// Whether Jamf is managing this computer.
    var isManaged: Bool {
        general?.remoteManagement?.managed ?? false
    }

    /// Matches a free-text query against the computer's name, serial, assigned user and email.
    /// An empty or whitespace-only query matches everything.
    func matches(_ searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let fields = [general?.name, hardware?.serialNumber, assignedUserDisplayName, assignedUserEmail]
        return fields.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }
}

// MARK: - Sort helpers
// Non-optional projections used as KeyPathComparator key paths. SwiftUI's
// `KeyPathComparator` needs a non-optional `Comparable` value path, so we
// surface stable empty-string / zero / false fallbacks here.
extension ComputerInventoryRecord {
    var sortName: String { general?.name ?? "" }
    var sortModel: String { hardware?.model ?? "" }
    var sortSerial: String { hardware?.serialNumber ?? "" }
    /// Expressed via `assignedUserDisplayName` so the User column sorts on exactly the value it shows.
    var sortRealName: String { assignedUserDisplayName ?? "" }
    var sortEmail: String { assignedUserEmail ?? "" }
    var sortLastContact: String { general?.lastContactTime ?? "" }
    /// 1 = managed, 0 = unmanaged. Int-typed so it shares a `V` type with `sortIntId`,
    /// which helps SwiftUI's @TableColumnBuilder unify column types.
    var sortManagedRank: Int { isManaged ? 1 : 0 }
    var sortIntId: Int { intId }
}

// MARK: - Profiles (Bulletproof)
struct ComputerProfile: Identifiable, Codable, Hashable {
    // We generate a unique ID for the UI to prevent "Duplicate ID" crashes
    let id = UUID()
    
    let jamfId: String? // Pro API returns IDs as Strings usually
    let displayName: String? // Pro API often uses 'displayName'
    let identifier: String?
    let username: String?
    
    // Fallback coding keys to handle variations
    enum CodingKeys: String, CodingKey {
        case jamfId = "id"
        case displayName, identifier, username
    }
}
