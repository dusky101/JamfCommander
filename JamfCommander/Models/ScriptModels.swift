//
//  ScriptModels.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import Foundation

// MARK: - Pro API List Response
struct ScriptListResponse: Codable {
    let totalCount: Int
    let results: [ScriptRecord]
}

// MARK: - Script Record
struct ScriptRecord: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let info: String?
    let notes: String?
    let priority: String? // e.g., "BEFORE", "AFTER"
    let categoryId: String?
    let categoryName: String?
    let osRequirements: String?
    let scriptContents: String?
    
    // Parameters 4-11
    let parameter4: String?
    let parameter5: String?
    let parameter6: String?
    let parameter7: String?
    let parameter8: String?
    let parameter9: String?
    let parameter10: String?
    let parameter11: String?
    
    // Helper: Convert String ID to Int for UI compatibility (InspectorSelection)
    var intId: Int { Int(id) ?? 0 }
    
    // Helper: Safe Category Name for Grouping
    var safeCategory: String { categoryName ?? "Uncategorised" }
}
