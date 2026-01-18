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
}

struct PolicyGeneral: Codable {
    let id: Int
    let name: String
    let enabled: Bool
    let category: PolicyCategory?
}

struct PolicyCategory: Codable {
    let id: Int
    let name: String
}

struct PolicyScope: Codable, Hashable {
    let all_computers: Bool
    let computers: [PolicyComputerTarget]?
    // Add groups if needed later
}

struct PolicyComputerTarget: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
}
