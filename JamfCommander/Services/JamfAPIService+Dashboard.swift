//
//  JamfAPIService+Dashboard.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//

import Foundation

// Helper Model for dashboard computers with user info
struct BasicComputerRecord: Codable, Identifiable {
    let id: Int
    let name: String
    let username: String?
    let realname: String?
    let email: String?
    
    init(from computer: ComputerInventoryRecord) {
        self.id = computer.intId
        self.name = computer.general?.name ?? "Unknown"
        self.username = computer.userAndLocation?.username
        self.realname = computer.userAndLocation?.realname
        self.email = computer.userAndLocation?.email
    }
    
    // Extract email domain for grouping
    var emailDomain: String {
        guard let email = email, !email.isEmpty else {
            return "No Email Domain"
        }
        
        if let atIndex = email.lastIndex(of: "@") {
            let domain = String(email[email.index(after: atIndex)...])
            return domain.isEmpty ? "No Email Domain" : domain
        }
        
        return "No Email Domain"
    }
}

extension JamfAPIService {
    
    // MARK: - Computer Functions
    
    func fetchDashboardComputers() async throws -> [BasicComputerRecord] {
        // First, get the list of all computers (fast, basic info only)
        let endpoint = "api/v3/computers-inventory?section=GENERAL&section=USER_AND_LOCATION&page-size=2000"
        
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfProComputerListResponse.self
        )
        
        // Convert to BasicComputerRecord with user info
        return response.results.map { BasicComputerRecord(from: $0) }
            .sorted { $0.name < $1.name }
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
