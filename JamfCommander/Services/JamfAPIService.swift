//
//  JamfAPIService.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI
import Combine

class JamfAPIService: ObservableObject {
    private var baseURL: String = ""
    private var token: String?
    
    enum APIError: Error {
        case invalidURL
        case authFailed
        case requestFailed
        case decodingFailed
        case unknown(String)
    }
    
    // MARK: - Authentication
    func authenticate(url: String, clientId: String, clientSecret: String) async throws {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines).dropLast(url.hasSuffix("/") ? 1 : 0)
        self.baseURL = String(cleanURL)
        
        guard let endpoint = URL(string: "\(self.baseURL)/api/v1/oauth/token") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyComponents = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        let bodyString = bodyComponents.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.authFailed
        }
        
        struct OAuthResponse: Codable { let access_token: String }
        let tokenResponse = try JSONDecoder().decode(OAuthResponse.self, from: data)
        self.token = tokenResponse.access_token
    }
    
    // MARK: - Data Fetching
    
    func fetchProfiles() async throws -> [ConfigProfile] {
        // STRATEGY: "Profile First Crawl" (Bulletproof)
        // 1. Fetch the Basic List (Reliable).
        // 2. Hydrate details (Category) in parallel.
        
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/JSSResource/osxconfigurationprofiles") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // 1. Get Basic List
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
        
        let listResponse = try JSONDecoder().decode(ClassicProfileListResponse.self, from: data)
        let basicProfiles = listResponse.os_x_configuration_profiles
        
        var richProfiles: [ConfigProfile] = []
        
        // 2. Hydrate in Parallel (Fetch Categories)
        // We limit concurrency to avoid slamming the API too hard (max 10-20 concurrent is usually safe)
        await withTaskGroup(of: ConfigProfile?.self) { group in
            for profile in basicProfiles {
                group.addTask {
                    do {
                        // Fetch details for this specific profile ID
                        let detail = try await self.fetchProfileScope(id: profile.id)
                        var enrichedProfile = profile
                        // Assign the category found in the details
                        enrichedProfile.categoryName = detail.general.category?.name ?? "Uncategorized"
                        return enrichedProfile
                    } catch {
                        // If detail fetch fails, return the basic profile (better than nothing!)
                        return profile
                    }
                }
            }
            
            for await result in group {
                if let p = result {
                    richProfiles.append(p)
                }
            }
        }
        
        return richProfiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func fetchCategories() async throws -> [Category] {
        // We still fetch the category list for the Filter Bar chips
        struct CategoryListResponse: Codable { let categories: [Category] }
        return try await genericFetch(endpoint: "JSSResource/categories", responseType: CategoryListResponse.self).categories
    }
    
    // MARK: - Script Functions (Pro API)
        
    func fetchScripts() async throws -> [ScriptRecord] {
        // We request specific fields to ensure we get Category and Contents for the inspector
        // Using page-size=2000 to get all scripts in one request
        let endpoint = "api/v1/scripts?page-size=2000&sort=name:asc"
        
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: ScriptListResponse.self
        )
        return response.results
    }
    
    func deleteScript(id: String) async throws {
        // Pro API delete endpoint
        try await genericRequest(method: "DELETE", endpoint: "api/v1/scripts/\(id)")
    }
    
    // MARK: - Policy Functions (Classic API)
        
        func fetchPolicies() async throws -> [Policy] {
            // 1. Fetch Basic List
            let endpoint = "JSSResource/policies"
            let listResponse = try await genericFetch(endpoint: endpoint, responseType: PolicyListResponse.self)
            
            // 2. Hydrate Details (to get Categories & Enabled State)
            // We limit concurrency to avoid overwhelming the server
            var detailedPolicies: [Policy] = []
            
            await withTaskGroup(of: Policy?.self) { group in
                for item in listResponse.policies {
                    group.addTask {
                        do {
                            // Fetch full detail for this policy
                            let detail = try await self.fetchPolicyDetail(id: item.id)
                            return Policy(
                                id: detail.general.id,
                                name: detail.general.name,
                                categoryId: detail.general.category?.id,
                                categoryName: detail.general.category?.name,
                                enabled: detail.general.enabled,
                                scope: detail.scope
                            )
                        } catch {
                            print("Failed to hydrate policy \(item.id): \(error)")
                            return nil
                        }
                    }
                }
                
                for await result in group {
                    if let policy = result {
                        detailedPolicies.append(policy)
                    }
                }
            }
            
            return detailedPolicies.sorted { $0.name < $1.name }
        }
        
        func fetchPolicyDetail(id: Int) async throws -> PolicyDetailXML {
            let response = try await genericFetch(
                endpoint: "JSSResource/policies/id/\(id)",
                responseType: PolicyDetailResponse.self
            )
            return response.policy
        }
        
        // Fetch Raw JSON for the Inspector Code View
        func fetchPolicyJSON(id: Int) async throws -> String {
            return try await fetchRawJSON(endpoint: "JSSResource/policies/id/\(id)")
        }
        
        func deletePolicy(id: Int) async throws {
            try await genericRequest(method: "DELETE", endpoint: "JSSResource/policies/id/\(id)")
        }
        
        func movePolicy(id: Int, toCategoryID: Int) async throws {
            let xml = """
            <policy>
                <general>
                    <category>
                        <id>\(toCategoryID)</id>
                    </category>
                </general>
            </policy>
            """
            try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
        }
    
    // MARK: - Computer Functions
        
    // Pro API (v1) - Returns detailed inventory records for the Dashboard
    func fetchComputers() async throws -> [ComputerInventoryRecord] {
        // We MUST request specific sections (GENERAL, HARDWARE) to get Name, Serial, and Managed Status.
        // We also add page-size=2000 to ensure we get the whole fleet in one go.
        let endpoint = "api/v1/computers-inventory?section=GENERAL&section=HARDWARE&page-size=2000"
        
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfProComputerListResponse.self
        )
        // Sort by name for a nice list
        return response.results.sorted { ($0.general?.name ?? "") < ($1.general?.name ?? "") }
    }
    
    // Pro API (v1) - Fetch single computer detail for the Inspector
    func fetchComputerDetail(id: Int) async throws -> ComputerInventoryRecord {
        // We MUST request CONFIGURATION_PROFILES to populate the "Profiles" tab.
        // We also request OS and Hardware for the "Info" tab.
        let endpoint = "api/v1/computers-inventory/\(id)?section=GENERAL&section=HARDWARE&section=OPERATING_SYSTEM&section=CONFIGURATION_PROFILES"
        
        return try await genericFetch(
            endpoint: endpoint,
            responseType: ComputerInventoryRecord.self
        )
    }
    
    // Fetch Raw JSON for the Editor
    func fetchProfileJSON(id: Int) async throws -> String {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/JSSResource/osxconfigurationprofiles/id/\(id)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { throw APIError.requestFailed }
        
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    // Fetch Parsed Scope & General Info
    func fetchProfileScope(id: Int) async throws -> ProfileDetail {
        return try await genericFetch(endpoint: "JSSResource/osxconfigurationprofiles/id/\(id)", responseType: ProfileDetailResponse.self).os_x_configuration_profile
    }
    
    // MARK: - Actions
    
    func deleteProfile(id: Int) async throws {
        try await genericRequest(method: "DELETE", endpoint: "JSSResource/osxconfigurationprofiles/id/\(id)")
    }
    
    func moveProfile(_ id: Int, toCategoryID categoryID: Int) async throws {
        let xmlString = """
        <os_x_configuration_profile>
            <general>
                <category>
                    <id>\(categoryID)</id>
                </category>
            </general>
        </os_x_configuration_profile>
        """
        try await genericRequest(method: "PUT", endpoint: "JSSResource/osxconfigurationprofiles/id/\(id)", body: xmlString)
    }
    
    // MARK: - Helpers
    
    func genericFetch<T: Codable>(endpoint: String, responseType: T.Type) async throws -> T {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { throw APIError.requestFailed }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func fetchRawJSON(endpoint: String) async throws -> String {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { throw APIError.requestFailed }
        
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    func genericRequest(method: String, endpoint: String, body: String? = nil) async throws {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body {
            request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data(using: .utf8)
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { throw APIError.requestFailed }
    }
}
