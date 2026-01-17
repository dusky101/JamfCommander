//
//  JamfAPIService.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI
import Combine

class JamfAPIService: ObservableObject {
    // We no longer store the URL persistently here; the View tells us what URL to use.
    private var baseURL: String = ""
    private var token: String?
    
    enum APIError: Error {
        case invalidURL
        case authFailed
        case requestFailed
        case decodingFailed
        case unknown(String)
    }
    
    // MARK: - Authentication (OAuth)
    func authenticate(url: String, clientId: String, clientSecret: String) async throws {
        // 1. Prepare URL
        // Fix: .dropLast() returns a Substring, so we cast it back to String
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines).dropLast(url.hasSuffix("/") ? 1 : 0)
        self.baseURL = String(cleanURL)
        
        guard let endpoint = URL(string: "\(self.baseURL)/api/v1/oauth/token") else { throw APIError.invalidURL }
        
        // 2. Prepare Request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // 3. Prepare Body (x-www-form-urlencoded)
        let bodyComponents = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        let bodyString = bodyComponents.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        // 4. Send Request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.authFailed
        }
        
        // 5. Decode Token
        struct OAuthResponse: Codable {
            let access_token: String
            let expires_in: Int
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthResponse.self, from: data)
        self.token = tokenResponse.access_token
    }
    
    // MARK: - Data Fetching
    
    func fetchProfiles() async throws -> [ConfigProfile] {
        try await genericFetch(endpoint: "JSSResource/osxconfigurationprofiles", responseType: ProfileListResponse.self).os_x_configuration_profiles
    }
    
    func fetchCategories() async throws -> [Category] {
        struct CategoryListResponse: Codable { let categories: [Category] }
        return try await genericFetch(endpoint: "JSSResource/categories", responseType: CategoryListResponse.self).categories
    }
    
    // NEW: Fetch full profile details (XML) for the Inspector View
    func fetchProfileDetails(id: Int) async throws -> String {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/JSSResource/osxconfigurationprofiles/id/\(id)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // We explicitly ask for XML here so it looks like "code" in the inspector
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
        
        return String(data: data, encoding: .utf8) ?? "Unable to decode profile."
    }
    
    // MARK: - Actions
    
    func deleteProfile(id: Int) async throws {
        try await genericRequest(method: "DELETE", endpoint: "JSSResource/osxconfigurationprofiles/id/\(id)")
    }
    
    func moveProfile(_ id: Int, toCategoryID categoryID: Int) async throws {
        // FIXED: The Classic API requires the category to be nested inside a <general> tag
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
    
    private func genericFetch<T: Codable>(endpoint: String, responseType: T.Type) async throws -> T {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func genericRequest(method: String, endpoint: String, body: String? = nil) async throws {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT" // Default to PUT for updates
        if method == "DELETE" {
            request.httpMethod = "DELETE"
        }
        
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data(using: .utf8)
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
    }
}
