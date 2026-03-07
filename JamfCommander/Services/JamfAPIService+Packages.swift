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
