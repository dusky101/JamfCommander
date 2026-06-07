//
//  JamfAPIService+Packages.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import Combine

extension JamfAPIService {
    
    /// Custom error type for policy creation with better messaging
    enum PolicyCreationError: LocalizedError {
        case conflict(String)
        case serverError(Int, String)
        
        var errorDescription: String? {
            switch self {
            case .conflict(let name):
                return "A policy named '\(name)' already exists. Skipped."
            case .serverError(let code, let detail):
                return "Server error (\(code)): \(detail)"
            }
        }
    }
    
    // MARK: - Installomator Discovery
    
    /// Represents a deployed Installomator policy discovered in Jamf
    struct InstallomatorPolicyInfo {
        let policyID: Int
        let policyName: String
        let label: String
        let categoryName: String?
        let enabled: Bool
    }
    
    /// Fetches all policies from Jamf and filters to those using an Installomator script.
    /// Hydrates policy details in batches of 10 with retry logic, then extracts the label from parameter4.
    func fetchInstallomatorPolicies() async throws -> [InstallomatorPolicyInfo] {
        print("[Installomator] Starting fetchInstallomatorPolicies...")
        
        let listResponse = try await genericFetch(
            endpoint: "JSSResource/policies",
            responseType: PolicyListResponse.self
        )
        print("[Installomator] Fetched \(listResponse.policies.count) policies from Jamf")
        
        var results: [InstallomatorPolicyInfo] = []
        
        let batchSize = 10
        let batches = stride(from: 0, to: listResponse.policies.count, by: batchSize).map {
            Array(listResponse.policies[$0..<min($0 + batchSize, listResponse.policies.count)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: InstallomatorPolicyInfo?.self) { group in
                for item in batch {
                    group.addTask {
                        for attempt in 1...3 {
                            do {
                                let detail = try await self.fetchPolicyDetail(id: item.id)
                                
                                guard let scripts = detail.scripts, !scripts.isEmpty else { return nil }
                                
                                for script in scripts {
                                    if script.name.localizedCaseInsensitiveContains("installomator"),
                                       let label = script.parameter4, !label.isEmpty {
                                        return InstallomatorPolicyInfo(
                                            policyID: detail.general.id,
                                            policyName: detail.general.name,
                                            label: label,
                                            categoryName: detail.general.category?.name,
                                            enabled: detail.general.enabled
                                        )
                                    }
                                }
                                return nil
                            } catch {
                                if attempt == 3 { return nil }
                                try? await Task.sleep(nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000))
                            }
                        }
                        return nil
                    }
                }
                
                for await result in group {
                    if let info = result {
                        results.append(info)
                    }
                }
            }
            
            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        print("[Installomator] Found \(results.count) deployed Installomator policies")
        return results
    }
    
    /// Fetches the Installomator Labels.txt from GitHub and parses individual labels.
    /// Each non-empty, non-comment line that matches the label pattern is extracted.
    func fetchInstallomatorLabelsFromGitHub() async throws -> [String] {
        let urlString = "https://raw.githubusercontent.com/Installomator/Installomator/main/Labels.txt"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        var labels: [String] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if !trimmed.contains(" ") {
                labels.append(trimmed)
            }
        }
        
        print("[Installomator] Parsed \(labels.count) labels from GitHub")
        return labels
    }
    
    // MARK: - Policy Creation
    
    /// Creates a Policy to install software via Installomator (Async Version)
    func createInstallomatorPolicyAsync(
        appName: String,
        label: String,
        categoryName: String,
        scriptID: String,
        featureOnMainPage: Bool,
        displayInSelfServiceCategory: Bool,
        scopeConfig: DeploymentScopeConfig? = nil,
        policyNameTemplate: String = "Install {appName}"
    ) async throws {
        
        let endpoint = "\(baseURL)/JSSResource/policies/id/0"
        let policyName = policyNameTemplate.replacingOccurrences(of: "{appName}", with: appName)
        let scope = scopeConfig ?? DeploymentScopeConfig()
        
        // Convert bools to explicit strings for XML safety
        let featMain = featureOnMainPage ? "true" : "false"
        let dispInCat = displayInSelfServiceCategory ? "true" : "false"
        
        // Generate scope XML from the configuration
        let scopeXML = scope.toScopeXML()
        
        let xmlBody = """
        <policy>
            <general>
                <name>\(policyName)</name>
                <enabled>true</enabled>
                <frequency>Ongoing</frequency>
                <category>
                    <name>\(categoryName)</name>
                </category>
            </general>
            \(scopeXML)
            <self_service>
                <use_for_self_service>true</use_for_self_service>
                <self_service_display_name>\(policyName)</self_service_display_name>
                <install_button_text>Install</install_button_text>
                <force_users_to_view_description>false</force_users_to_view_description>
                
                <feature_on_main_page>\(featMain)</feature_on_main_page>
                
                <self_service_categories>
                    <category>
                        <name>\(categoryName)</name>
                        <display_in>\(dispInCat)</display_in>
                        <feature_in>\(featMain)</feature_in>
                    </category>
                </self_service_categories>
            </self_service>
            <scripts>
                <script>
                    <id>\(scriptID)</id>
                    <priority>After</priority>
                    <parameter4>\(label)</parameter4>
                    <parameter5>DEBUG=0</parameter5>
                    <parameter6>NOTIFY=silent</parameter6>
                </script>
            </scripts>
        </policy>
        """
        
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = xmlBody.data(using: .utf8)
        
        if let token = self.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Jamf API Error (\(httpResponse.statusCode)): \(errorBody)")
            
            // HTTP 409 = Conflict (duplicate policy name — e.g. "Install Homebrew" already exists)
            if httpResponse.statusCode == 409 {
                throw PolicyCreationError.conflict(policyName)
            }
            
            throw PolicyCreationError.serverError(httpResponse.statusCode, errorBody)
        }
    }
}
