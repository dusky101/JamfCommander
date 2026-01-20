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

struct ConfigProfile: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    var categoryName: String = "Uncategorized" // Default state
    
    // Standard Init
    init(id: Int, name: String, categoryName: String = "Uncategorized") {
        self.id = id
        self.name = name
        self.categoryName = categoryName
    }
    
    // Decoding just ID and Name from the basic list
    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct Category: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}

struct ComputerGroup: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Detailed Models (For Crawling & Inspector)

struct ProfileDetailResponse: Codable {
    let os_x_configuration_profile: ProfileDetail
}

struct ProfileDetail: Codable {
    let general: GeneralInfo
    let scope: ScopeInfo
}

struct GeneralInfo: Codable {
    let id: Int
    let name: String
    let description: String?
    let category: CategoryWrapper? // NEW: Added this to capture category info
}

// Helper to decode the nested <category><name>...</name></category>
struct CategoryWrapper: Codable {
    let id: Int
    let name: String
}

struct ScopeInfo: Codable {
    let all_computers: Bool
    let computers: [BasicComputer]?
    let computer_groups: [BasicGroup]?
    
    struct BasicComputer: Codable, Identifiable {
        let id: Int
        let name: String
    }
    struct BasicGroup: Codable, Identifiable {
        let id: Int
        let name: String
    }
}

// MARK: - UI Helpers

enum JamfItemStatus: String, CaseIterable, Identifiable {
    case active = "Active"
    case inactive = "Inactive" // Added
    case pending = "Pending"
    case failed = "Failed"
    case unknown = "Unknown"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .active: return .green
        case .inactive: return .gray // Added
        case .pending: return .orange
        case .failed: return .red
        case .unknown: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .inactive: return "xmark.circle" // Added
        case .pending: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
