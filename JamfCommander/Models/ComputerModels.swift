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
    
    // Helper to Convert String ID to Int (for compatibility with UI)
    var intId: Int { Int(id) ?? 0 }
}

// MARK: - Sections

struct ComputerGeneral: Codable, Hashable {
    let name: String
    let lastIpAddress: String?
    let lastReportedIp: String?
    let lastContactTime: String?
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
