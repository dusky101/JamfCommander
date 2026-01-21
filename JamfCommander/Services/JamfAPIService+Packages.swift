//
//  JamfAPIService+Packages.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import Combine

extension JamfAPIService {
    
    /// Creates a Policy to install software via Installomator (Async Version)
    func createInstallomatorPolicyAsync(
        appName: String,
        label: String,
        categoryName: String,
        scriptID: String,
        featureOnMainPage: Bool,
        displayInSelfServiceCategory: Bool
    ) async throws {
        
        let endpoint = "\(baseURL)/JSSResource/policies/id/0"
        
        // Convert bools to explicit strings for XML safety
        let featMain = featureOnMainPage ? "true" : "false"
        let dispInCat = displayInSelfServiceCategory ? "true" : "false"
        
        let xmlBody = """
        <policy>
            <general>
                <name>Install \(appName)</name>
                <enabled>true</enabled>
                <frequency>Ongoing</frequency>
                <category>
                    <name>\(categoryName)</name>
                </category>
            </general>
            <scope>
                <all_computers>true</all_computers>
            </scope>
            <self_service>
                <use_for_self_service>true</use_for_self_service>
                <self_service_display_name>Install \(appName)</self_service_display_name>
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
            if let errorStr = String(data: data, encoding: .utf8) {
                print("Jamf API Error: \(errorStr)")
            }
            throw URLError(.badServerResponse)
        }
    }
}
