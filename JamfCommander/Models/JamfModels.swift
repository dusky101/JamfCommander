//
//  JamfModels.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import Foundation
import SwiftUI

// MARK: - API Response Wrappers

struct ClassicProfileListResponse: Codable {
    let os_x_configuration_profiles: [ConfigProfile]
}

struct CategoryListResponse: Codable {
    let categories: [Category]
}

// MARK: - Core Data Models

struct ConfigProfile: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    var categoryName: String = "Uncategorised" // Default state
    var isActive: Bool = true // NEW: Determined by scope (default true until we fetch details)
    
    // Standard Init
    init(id: Int, name: String, categoryName: String = "Uncategorised", isActive: Bool = true) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.isActive = isActive
    }
    
    // Decoding just ID and Name from the basic list
    enum CodingKeys: String, CodingKey {
        case id, name
    }
    
    // Compute status based on isActive
    var status: JamfItemStatus {
        return isActive ? .active : .inactive
    }
}

struct Category: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}

struct ComputerGroup: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let smartGroup: Bool?
    let memberCount: Int?
    
    var groupTypeLabel: String {
        smartGroup == true ? "Smart" : "Static"
    }
    
    var groupTypeIcon: String {
        smartGroup == true ? "gearshape.2.fill" : "person.3.fill"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case smartGroup
        case isSmart
        case is_smart
        case memberCount
        case computerCount
        case count
    }
    
    init(id: Int, name: String, smartGroup: Bool? = nil, memberCount: Int? = nil) {
        self.id = id
        self.name = name
        self.smartGroup = smartGroup
        self.memberCount = memberCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = intID
        } else {
            let stringID = try container.decode(String.self, forKey: .id)
            id = Int(stringID) ?? 0
        }
        name = try container.decode(String.self, forKey: .name)
        smartGroup = try container.decodeIfPresent(Bool.self, forKey: .smartGroup)
            ?? container.decodeIfPresent(Bool.self, forKey: .isSmart)
            ?? container.decodeIfPresent(Bool.self, forKey: .is_smart)
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount)
            ?? container.decodeIfPresent(Int.self, forKey: .computerCount)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(smartGroup, forKey: .smartGroup)
        try container.encodeIfPresent(memberCount, forKey: .memberCount)
    }
}

// MARK: - Detailed Models (For Crawling & Inspector)

struct ProfileDetailResponse: Codable {
    let os_x_configuration_profile: ProfileDetail
}

struct ProfileDetail: Codable, Sendable {
    let general: GeneralInfo
    let scope: ScopeInfo
    
    // Determine if profile is scoped based on scope
    nonisolated var isActive: Bool {
        // Scoped if deployed to all computers
        if scope.all_computers {
            return true
        }
        // Scoped if targeted to any specific computers or groups
        let hasComputers = !(scope.computers?.isEmpty ?? true)
        let hasGroups = !(scope.computer_groups?.isEmpty ?? true)
        return hasComputers || hasGroups
    }
}

struct GeneralInfo: Codable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let category: CategoryWrapper? // NEW: Added this to capture category info
    let distribution_method: String?
    let level: String? // "System" or "User"
    let user_removable: Bool?
    let redeploy_on_update: String? // "Newly Assigned", "All", etc.
}

// Helper to decode the nested <category><name>...</name></category>
struct CategoryWrapper: Codable, Sendable {
    let id: Int
    let name: String
}

struct ScopeInfo: Codable, Sendable {
    let all_computers: Bool
    let computers: [BasicComputer]?
    let computer_groups: [BasicGroup]?
    let exclusions: Exclusions?
    
    struct BasicComputer: Codable, Identifiable, Sendable {
        let id: Int
        let name: String
    }
    struct BasicGroup: Codable, Identifiable, Sendable {
        let id: Int
        let name: String
    }
    struct Exclusions: Codable, Sendable {
        let computers: [BasicComputer]?
        let computer_groups: [BasicGroup]?
    }
}

// MARK: - UI Helpers

enum JamfItemStatus: String, CaseIterable, Identifiable {
    case active = "Scoped"
    case inactive = "Unscoped"
    case pending = "Pending"
    case failed = "Failed"
    case unknown = "Unknown"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .active: return .green
        case .inactive: return .gray
        case .pending: return .orange
        case .failed: return .red
        case .unknown: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .inactive: return "xmark.circle"
        case .pending: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
