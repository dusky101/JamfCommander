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
    /// When Jamf last heard from this Mac, as Jamf reports it — ISO 8601, or `nil` for a machine
    /// that has never checked in.
    ///
    /// It arrives in the `GENERAL` section this fetch already asks for, and `ComputerGeneral` has
    /// always decoded it. It was simply not copied here, which is why the Dashboard's Device Status
    /// section had no date to work from and drew every machine as "Active" regardless. Nothing extra
    /// is requested to carry it: see `DeviceContact` for what is made of it.
    let lastContactTime: String?

    init(from computer: ComputerInventoryRecord) {
        self.id = computer.intId
        self.name = computer.general?.name ?? "Unknown"
        self.username = computer.userAndLocation?.username
        self.realname = computer.userAndLocation?.realname
        self.email = computer.userAndLocation?.email
        self.lastContactTime = computer.general?.lastContactTime
    }
    
    /// How long ago Jamf last heard from this Mac, and therefore which state it is in.
    var contactAge: TimeInterval? { DeviceContactClock.age(since: lastContactTime) }
    var contactState: DeviceContactState { DeviceContactState.state(forAge: contactAge) }

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
    
    func fetchDashboardComputers(bypassingCache: Bool = false) async throws -> [BasicComputerRecord] {
        // First, get the list of all computers (fast, basic info only)
        let endpoint = "api/v3/computers-inventory?section=GENERAL&section=USER_AND_LOCATION&page-size=2000"

        // A lighter read than the Computers module's `fetchComputers()`, and a different type, so
        // it has a cache entry of its own. Both live in the `.computers` domain and fall together.
        if let cached = cachedValue(.dashboardComputers, as: [BasicComputerRecord].self, bypassingCache: bypassingCache) {
            return cached
        }
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfProComputerListResponse.self
        )

        // Convert to BasicComputerRecord with user info
        let fresh = response.results.map { BasicComputerRecord(from: $0) }
            .sorted { $0.name < $1.name }
        storeInCache(fresh, as: .dashboardComputers)
        return fresh
    }
    
    // MARK: - Category Management Functions
    
    func createCategory(name: String) async throws {
        let xml = "<category><name>\(Self.xmlEscape(name))</name><priority>9</priority></category>"
        let endpoint = "JSSResource/categories/id/0" // ID 0 POST creates new
        try await genericRequest(method: "POST", endpoint: endpoint, body: xml)
    }
    
    func updateCategory(id: Int, newName: String) async throws {
        let xml = "<category><name>\(Self.xmlEscape(newName))</name></category>"
        let endpoint = "JSSResource/categories/id/\(id)"
        try await genericRequest(method: "PUT", endpoint: endpoint, body: xml)
    }
    
    func deleteCategory(id: Int) async throws {
        let endpoint = "JSSResource/categories/id/\(id)"
        try await genericRequest(method: "DELETE", endpoint: endpoint)
    }
}
