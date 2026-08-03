//
//  JamfAPIService+Cloning.swift
//  JamfCommander
//
//  Created by Marc Oliff on 23/02/2026.
//

import Foundation

extension JamfAPIService {
    
    // MARK: - Policy Cloning
    
    /// Clones an existing policy with optional stripping of scope, triggers, frequency, and self service
    func clonePolicy(
        id: Int,
        newName: String,
        toCategoryID: Int,
        stripScope: Bool,
        stripTriggers: Bool,
        stripFrequency: Bool,
        disableSelfService: Bool
    ) async throws -> Int {
        // 1. Fetch complete policy XML (includes all sections: packages, scripts, self_service, etc.)
        let completeXML = try await fetchRawPolicyXML(id: id)
        
        // 2. Modify the XML to update name, category, scope, triggers, frequency
        var modifiedXML = completeXML
        
        // IMPORTANT: Replace category ID FIRST before replacing name
        // (otherwise we might replace the category name instead of policy name)
        modifiedXML = replaceXMLCategoryID(in: modifiedXML, newCategoryID: toCategoryID)
        
        // Now replace the policy name within <general> section
        modifiedXML = replacePolicyName(in: modifiedXML, newName: xmlEscape(newName))
        
        // Set enabled to false for safety
        modifiedXML = replaceXMLElement(in: modifiedXML, element: "enabled", newValue: "false")
        
        // Strip scope if requested
        if stripScope {
            let emptyScope = """
            <scope>
                <all_computers>false</all_computers>
                <computers/>
                <computer_groups/>
                <buildings/>
                <departments/>
                <limit_to_users/>
                <limitations/>
                <exclusions/>
            </scope>
            """
            modifiedXML = replaceScopeSection(in: modifiedXML, newScope: emptyScope)
        }
        
        // Strip triggers if requested
        if stripTriggers {
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_checkin", newValue: "false")
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_enrollment_complete", newValue: "false")
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_login", newValue: "false")
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_logout", newValue: "false")
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_network_state_changed", newValue: "false")
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_startup", newValue: "false")
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "trigger_other", newValue: "")
        }
        
        // Strip frequency if requested
        if stripFrequency {
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "frequency", newValue: "Once per computer")
        }
        
        // Disable Self Service if requested
        if disableSelfService {
            modifiedXML = replaceXMLElement(in: modifiedXML, element: "use_for_self_service", newValue: "false")
        }
        
        // 3. POST to create new policy
        let endpoint = "\(baseURL)/JSSResource/policies/id/0"
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        guard let token = token else { throw APIError.authFailed }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = modifiedXML.data(using: .utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorStr = String(data: data, encoding: .utf8) {
                print("Jamf API Error: \(errorStr)")
            }
            throw APIError.requestFailed
        }
        
        // 4. Parse response to extract new ID
        let newID = try parseIDFromXMLResponse(data: data, elementName: "id")
        RefreshCoordinator.shared.requestRefresh()
        return newID
    }
    
    // MARK: - Profile Cloning
    
    /// Clones an existing profile with optional stripping of scope
    func cloneProfile(
        id: Int,
        newName: String,
        toCategoryID: Int,
        stripScope: Bool
    ) async throws -> Int {
        // 1. Fetch complete profile XML (includes all payloads and settings)
        let completeXML = try await fetchRawProfileXML(id: id)
        
        // 2. Modify the XML to update name, category, and scope
        var modifiedXML = completeXML
        
        // IMPORTANT: Replace category ID FIRST before replacing name
        modifiedXML = replaceProfileCategoryID(in: modifiedXML, newCategoryID: toCategoryID)
        
        // Now replace the profile name within <general> section
        modifiedXML = replaceProfileName(in: modifiedXML, newName: xmlEscape(newName))
        
        // Strip scope if requested
        if stripScope {
            let emptyScope = """
            <scope>
                <all_computers>false</all_computers>
                <computers/>
                <computer_groups/>
                <buildings/>
                <departments/>
                <jss_users/>
                <jss_user_groups/>
                <limitations/>
                <exclusions/>
            </scope>
            """
            modifiedXML = replaceScopeSection(in: modifiedXML, newScope: emptyScope)
        }
        
        // 3. POST to create new profile
        let endpoint = "\(baseURL)/JSSResource/osxconfigurationprofiles/id/0"
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        guard let token = token else { throw APIError.authFailed }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = modifiedXML.data(using: .utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorStr = String(data: data, encoding: .utf8) {
                print("Jamf API Error: \(errorStr)")
            }
            throw APIError.requestFailed
        }
        
        // 4. Parse response to extract new ID
        let newID = try parseIDFromXMLResponse(data: data, elementName: "id")
        RefreshCoordinator.shared.requestRefresh()
        return newID
    }

    // MARK: - Bulk Policy Cloning

    /// Clones each policy in the plan and then applies its templated custom trigger (and,
    /// when configured, a frequency) to the new clone. Rate-limited (batches of 5 + 0.5s
    /// gaps); a per-item failure is captured and the batch continues. Returns one
    /// `OperationResult` per item for `OperationResultView`.
    func bulkClonePolicies(_ items: [BulkClonePlanItem], config: BulkCloneConfig) async -> [OperationResult] {
        var results: [OperationResult] = []
        let batchSize = 5
        let batches = stride(from: 0, to: items.count, by: batchSize).map {
            Array(items[$0..<min($0 + batchSize, items.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: OperationResult.self) { group in
                for item in batch {
                    group.addTask {
                        let newId: Int
                        do {
                            newId = try await self.clonePolicy(
                                id: item.policyId,
                                newName: item.newName,
                                toCategoryID: config.targetCategoryID,
                                stripScope: config.stripScope,
                                stripTriggers: config.stripTriggers,
                                stripFrequency: config.stripFrequency,
                                disableSelfService: config.disableSelfService
                            )
                        } catch {
                            return OperationResult(itemName: item.newName, success: false, error: "Clone failed: \(error)")
                        }

                        // Apply the templated custom trigger and/or the chosen frequency.
                        let trigger = item.trimmedCustomTrigger.isEmpty ? nil : item.trimmedCustomTrigger
                        if config.applyFrequency != nil || trigger != nil {
                            do {
                                try await self.applyClonedGeneral(id: newId, frequency: config.applyFrequency, customTrigger: trigger)
                            } catch {
                                return OperationResult(
                                    itemName: item.newName,
                                    success: false,
                                    error: "Created (ID \(newId)) but couldn't set trigger/frequency — set it manually."
                                )
                            }
                        }

                        return OperationResult(itemName: item.newName, success: true, error: nil, toCategory: "Created (ID: \(newId))")
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }

            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return results
    }

    /// Writes only the supplied `<general>` elements (a partial update) so a clone's
    /// custom trigger / frequency can be set without clobbering its other general fields.
    /// Every dynamic value is XML-escaped.
    private func applyClonedGeneral(id: Int, frequency: PolicyFrequency?, customTrigger: String?) async throws {
        var elements = ""
        if let frequency {
            elements += "<frequency>\(Self.xmlEscape(frequency.jamfValue))</frequency>"
        }
        if let customTrigger, !customTrigger.isEmpty {
            elements += "<trigger_other>\(Self.xmlEscape(customTrigger))</trigger_other>"
        }
        guard !elements.isEmpty else { return }
        let xml = "<policy><general>\(elements)</general></policy>"
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    // MARK: - Helper Methods
    
    /// Fetches complete raw XML for a profile including all payloads
    private func fetchRawProfileXML(id: Int) async throws -> String {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/JSSResource/osxconfigurationprofiles/id/\(id)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw APIError.decodingFailed
        }
        
        return xmlString
    }
    
    /// Replaces the category ID within a profile's general section
    private func replaceProfileCategoryID(in xml: String, newCategoryID: Int) -> String {
        // Match <category>...</category> and replace entire category block
        let pattern = "<category>.*?</category>"
        let replacement = "<category><id>\(newCategoryID)</id></category>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        // Only replace the FIRST occurrence (which should be in <general>)
        guard let match = regex.firstMatch(in: xml, options: [], range: range) else {
            return xml
        }
        
        let matchRange = match.range
        guard let swiftRange = Range(matchRange, in: xml) else {
            return xml
        }
        
        var result = xml
        result.replaceSubrange(swiftRange, with: replacement)
        return result
    }
    
    /// Replaces the profile name within the general section
    private func replaceProfileName(in xml: String, newName: String) -> String {
        // Match <general>...<name>...</name>...</general> within os_x_configuration_profile
        let pattern = "(<general>.*?<name>).*?(</name>)"
        let replacement = "$1\(newName)$2"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: replacement)
    }
    
    /// Fetches complete raw XML for a policy including all sections
    private func fetchRawPolicyXML(id: Int) async throws -> String {
        guard let token = token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/JSSResource/policies/id/\(id)") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestFailed
        }
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw APIError.decodingFailed
        }
        
        return xmlString
    }
    
    /// Replaces an XML element's value
    private func replaceXMLElement(in xml: String, element: String, newValue: String) -> String {
        let pattern = "<\(element)>.*?</\(element)>"
        let replacement = "<\(element)>\(newValue)</\(element)>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: replacement)
    }
    
    /// Replaces the category ID within the general section
    private func replaceXMLCategoryID(in xml: String, newCategoryID: Int) -> String {
        // Match <category><id>123</id></category> or <category><id>123</id><name>...</name></category>
        // and replace entire category block with just the ID
        let pattern = "<category>.*?</category>"
        let replacement = "<category><id>\(newCategoryID)</id></category>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        // Only replace the FIRST occurrence (which should be in <general>)
        guard let match = regex.firstMatch(in: xml, options: [], range: range) else {
            return xml
        }
        
        let matchRange = match.range
        guard let swiftRange = Range(matchRange, in: xml) else {
            return xml
        }
        
        var result = xml
        result.replaceSubrange(swiftRange, with: replacement)
        return result
    }
    
    /// Replaces the policy name within the general section
    private func replacePolicyName(in xml: String, newName: String) -> String {
        // Match <general>...<name>...</name>...</general> and replace the name
        // Use a more specific pattern to only match within <general> section
        let pattern = "(<general>.*?<name>).*?(</name>)"
        let replacement = "$1\(newName)$2"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: replacement)
    }
    
    /// Replaces the entire scope section
    private func replaceScopeSection(in xml: String, newScope: String) -> String {
        let pattern = "<scope>.*?</scope>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return xml
        }
        
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: newScope)
    }
    
    /// Escapes special XML characters in strings
    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    /// Parses ID from XML response
    /// Reads an id back out of a Classic-API create response (`<id>123</id>`). Shared with the
    /// Installomator creation path, which needs the new policy id to attach a Self Service icon.
    func parseIDFromXMLResponse(data: Data, elementName: String) throws -> Int {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw APIError.decodingFailed
        }
        
        // Simple XML parsing to extract ID
        // Look for pattern like <id>123</id>
        let pattern = "<\(elementName)>(\\d+)</\(elementName)>"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
           let range = Range(match.range(at: 1), in: xmlString) {
            let idString = String(xmlString[range])
            if let id = Int(idString) {
                return id
            }
        }
        
        throw APIError.decodingFailed
    }
}
