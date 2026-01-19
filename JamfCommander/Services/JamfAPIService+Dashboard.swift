//
//  JamfAPIService+Dashboard.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import Foundation

// Helper Model just for counting computers
struct BasicComputerListResponse: Codable {
    let computers: [BasicComputerRecord]
}
struct BasicComputerRecord: Codable {
    let id: Int
    let name: String
}

extension JamfAPIService {
    
    // MARK: - Computer Functions
    
    func fetchDashboardComputers() async throws -> [BasicComputerRecord] {
        let endpoint = "JSSResource/computers"
        let response = try await genericFetch(endpoint: endpoint, responseType: BasicComputerListResponse.self)
        return response.computers
    }
    
    // MARK: - Category Management Functions
    
    func createCategory(name: String) async throws {
        let xml = "<category><name>\(name)</name><priority>9</priority></category>"
        let endpoint = "JSSResource/categories/id/0" // ID 0 POST creates new
        try await genericRequest(method: "POST", endpoint: endpoint, body: xml)
    }
    
    func updateCategory(id: Int, newName: String) async throws {
        let xml = "<category><name>\(newName)</name></category>"
        let endpoint = "JSSResource/categories/id/\(id)"
        try await genericRequest(method: "PUT", endpoint: endpoint, body: xml)
    }
    
    func deleteCategory(id: Int) async throws {
        let endpoint = "JSSResource/categories/id/\(id)"
        try await genericRequest(method: "DELETE", endpoint: endpoint)
    }
}
