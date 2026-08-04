//
//  JamfAPIService+Packages.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import Combine

extension JamfAPIService {
    
    /// Why a policy creation attempt failed, phrased so an administrator can act on it.
    ///
    /// Deliberately carries **no** Jamf response body. Bodies can echo tenant data, so they are
    /// classified in memory (see `creationFailure(status:body:policyName:categoryName:)`) and then
    /// discarded — never logged, shown or exported (root `CLAUDE.md`, invariant 4).
    enum PolicyCreationError: LocalizedError {
        /// Jamf already has a policy with this name — policy names must be unique.
        case duplicateName(String)
        /// Jamf refused the target category, e.g. it was renamed or deleted since the list loaded.
        case categoryRejected(String)
        /// Jamf could not parse the request body.
        case malformedRequest
        /// HTTP 401 — the session was refused.
        case unauthorised
        /// HTTP 403 — the API client lacks the privilege to create policies.
        case insufficientPrivileges
        /// HTTP 404 — the endpoint or a referenced object (such as the script) was not found.
        case notFound
        /// HTTP 429 — Jamf is throttling.
        case rateLimited
        /// HTTP 5xx — Jamf itself failed, so the outcome is genuinely unknown.
        case serverFailure(Int)
        /// Any other non-2xx response.
        case unexpectedResponse(Int)
        /// The request never reached Jamf.
        case networkFailure(String)

        var errorDescription: String? {
            switch self {
            case .duplicateName(let name):
                return "A policy named '\(name)' already exists in Jamf. Change the policy name template, or deselect this item."
            case .categoryRejected(let category):
                return "Jamf rejected the category '\(category)'. It may have been renamed or deleted — reload the categories and choose again."
            case .malformedRequest:
                return "Jamf could not process the request for this item. Check the policy name and category for unusual characters, then try again."
            case .unauthorised:
                return "The Jamf session was refused (401). Reconnect to Jamf and try again."
            case .insufficientPrivileges:
                return "This API client is not permitted to create policies (403). It needs the 'Create Policies' privilege."
            case .notFound:
                return "Jamf could not find the policies endpoint or the selected script (404). Check the Installomator script still exists."
            case .rateLimited:
                return "Jamf is throttling requests (429). Wait a moment, then deploy the remaining items."
            case .serverFailure(let code):
                return "Jamf reported an internal error (HTTP \(code)). Check in Jamf whether the policy was created before retrying."
            case .unexpectedResponse(let code):
                return "Jamf rejected this item (HTTP \(code)). Check the policy name, category and script in Jamf."
            case .networkFailure(let reason):
                return "Could not reach Jamf: \(reason)"
            }
        }
    }

    /// What a Jamf error body indicates, extracted without retaining the body itself.
    private enum JamfRejectionHint {
        case duplicateName
        case category
        case malformedBody
        case none
    }

    // MARK: - Installomator Discovery

    /// Represents a deployed Installomator policy discovered in Jamf
    struct InstallomatorPolicyInfo: Sendable {
        let policyID: Int
        let policyName: String
        let label: String
        let categoryName: String?
        let enabled: Bool
        /// The version this policy pins, read back from an `appNewVersion=` override in
        /// parameter7–parameter11. `nil` means the policy lets Installomator pick the version.
        let pinnedVersion: String?
    }

    /// The outcome of one pass over the tenant's policies.
    struct InstallomatorScan: Sendable {
        /// Policies that run an Installomator script with a label in `parameter4`.
        let deployed: [InstallomatorPolicyInfo]
        /// Every policy name in the tenant. Used to spot name collisions — including with policies
        /// that install the same app but were made by hand and so aren't recognised as Installomator.
        let allPolicyNames: [String]
    }

    /// Reads back the version a policy pins, from an `appNewVersion=` override in
    /// parameter7–parameter11 — the same parameters the deployment sheet writes.
    ///
    /// Position isn't fixed: Installomator evaluates any argument containing `=` wherever it sits, so
    /// this searches all five rather than assuming the sheet's ordering. A policy edited by hand in
    /// Jamf is read just as happily as one this app created.
    /// `nonisolated` because the scan calls it from inside a `TaskGroup`; it reads only its argument,
    /// so there is no actor state to protect.
    nonisolated private static func pinnedVersion(in script: PolicyScript) -> String? {
        let overrides = [
            script.parameter7, script.parameter8, script.parameter9,
            script.parameter10, script.parameter11,
        ]
        let prefix = "appNewVersion="

        for override in overrides {
            let value = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard value.hasPrefix(prefix) else { continue }
            let version = String(value.dropFirst(prefix.count))
            return version.isEmpty ? nil : version
        }
        return nil
    }

    /// Names of every policy in the tenant — one list request, no per-policy hydration.
    /// Used for the pre-flight duplicate-name check before a batch creation runs.
    func fetchPolicyNames() async throws -> [String] {
        let listResponse = try await genericFetch(
            endpoint: "JSSResource/policies",
            responseType: PolicyListResponse.self
        )
        return listResponse.policies.map(\.name)
    }

    /// Ids of the scripts that look like Installomator.
    ///
    /// Matching a policy's script by id as well as by name means a policy is still recognised when
    /// its payload omits the script name, and lets the caller add the script the administrator
    /// actually deploys with — which need not be called "Installomator" at all.
    func fetchInstallomatorScriptIDs() async throws -> Set<String> {
        let scripts = try await fetchScripts()
        return Set(
            scripts
                .filter { $0.name.localizedCaseInsensitiveContains("installomator") }
                .map(\.id)
        )
    }

    /// Fetches all policies from Jamf and filters to those using an Installomator script.
    /// Hydrates policy details in batches of 10 with retry logic, then extracts the label from parameter4.
    ///
    /// - Parameter knownScriptIDs: Additional script ids to treat as Installomator, so a renamed
    ///   or differently-named script is still detected (see `fetchInstallomatorScriptIDs()`).
    func fetchInstallomatorPolicies(knownScriptIDs: Set<String> = []) async throws -> InstallomatorScan {
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
                                    // Match by name *or* id: the policy payload can omit the script
                                    // name, and a tenant's Installomator script may be renamed.
                                    let isInstallomator = script.name.localizedCaseInsensitiveContains("installomator")
                                        || knownScriptIDs.contains(script.id)
                                    let label = script.parameter4?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    if isInstallomator, !label.isEmpty {
                                        return InstallomatorPolicyInfo(
                                            policyID: detail.general.id,
                                            policyName: detail.general.name,
                                            label: label,
                                            categoryName: detail.general.category?.name,
                                            enabled: detail.general.enabled,
                                            pinnedVersion: Self.pinnedVersion(in: script)
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
        return InstallomatorScan(
            deployed: results,
            allPolicyNames: listResponse.policies.map(\.name)
        )
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
        
        // Labels.txt is not guaranteed to be unique — at the time of writing `omnissahorizonclient`
        // appears twice. A duplicate would be offered twice and the second POST of a run would come
        // back as an HTTP 409 "already exists", reported as a failure the administrator can do
        // nothing about. De-duplicate case-insensitively, keeping first-seen order.
        var labels: [String] = []
        var seenKeys = Set<String>()
        var duplicatesDropped = 0
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.contains(" ") { continue }

            if seenKeys.insert(trimmed.lowercased()).inserted {
                labels.append(trimmed)
            } else {
                duplicatesDropped += 1
            }
        }

        print("[Installomator] Parsed \(labels.count) unique labels from GitHub (\(duplicatesDropped) duplicate line(s) ignored)")
        return labels
    }
    
    // MARK: - Policy Creation
    
    /// Creates a Policy to install software via Installomator (Async Version).
    ///
    /// - Returns: The new policy's id, read back from Jamf's create response, or `nil` if the
    ///   response carried no readable id. The policy exists either way, so a caller that wanted to
    ///   follow up (e.g. attaching a Self Service icon) must treat `nil` as "created but not
    ///   finished", never as a creation failure.
    @discardableResult
    func createInstallomatorPolicyAsync(
        appName: String,
        label: String,
        categoryName: String,
        scriptID: String,
        featureOnMainPage: Bool,
        displayInSelfServiceCategory: Bool,
        scopeConfig: DeploymentScopeConfig? = nil,
        policyNameTemplate: String = "Install {appName}",
        version: String? = nil,
        overrides: [String] = []
    ) async throws -> Int? {

        let endpoint = "\(baseURL)/JSSResource/policies/id/0"
        let policyName = Self.resolvePolicyName(template: policyNameTemplate, appName: appName, version: version)
        let scope = scopeConfig ?? DeploymentScopeConfig()
        
        // Convert bools to explicit strings for XML safety
        let featMain = featureOnMainPage ? "true" : "false"
        let dispInCat = displayInSelfServiceCategory ? "true" : "false"

        // Escape every dynamic value before it reaches the XML body. A category named
        // "Utilities & Tools" is perfectly legal in Jamf but produced malformed XML here,
        // which failed the whole deployment. `policyName` stays raw for user-facing messages
        // (the 409 conflict) and is escaped separately for the payload.
        let safePolicyName = Self.xmlEscape(policyName)
        let safeCategoryName = Self.xmlEscape(categoryName)
        let safeLabel = Self.xmlEscape(label)
        
        // Generate scope XML from the configuration
        let scopeXML = scope.toScopeXML()

        // Installomator re-reads its `key=value` arguments after the label runs, so these override
        // whatever the label computed. parameter4-6 are taken (label, DEBUG, NOTIFY), leaving 7-11.
        // Escaped like every other dynamic value — a pinned URL can legitimately contain `&`.
        let overrideParameters = overrides
            .prefix(InstallomatorOverrides.maximumOverrides)
            .enumerated()
            .map { index, value in
                "<parameter\(index + 7)>\(Self.xmlEscape(value))</parameter\(index + 7)>"
            }
            .joined(separator: "\n                    ")

        let xmlBody = """
        <policy>
            <general>
                <name>\(safePolicyName)</name>
                <enabled>true</enabled>
                <frequency>Ongoing</frequency>
                <category>
                    <name>\(safeCategoryName)</name>
                </category>
            </general>
            \(scopeXML)
            <self_service>
                <use_for_self_service>true</use_for_self_service>
                <self_service_display_name>\(safePolicyName)</self_service_display_name>
                <install_button_text>Install</install_button_text>
                <force_users_to_view_description>false</force_users_to_view_description>
                
                <feature_on_main_page>\(featMain)</feature_on_main_page>
                
                <self_service_categories>
                    <category>
                        <name>\(safeCategoryName)</name>
                        <display_in>\(dispInCat)</display_in>
                        <feature_in>\(featMain)</feature_in>
                    </category>
                </self_service_categories>
            </self_service>
            <scripts>
                <script>
                    <id>\(scriptID)</id>
                    <priority>After</priority>
                    <parameter4>\(safeLabel)</parameter4>
                    <parameter5>DEBUG=0</parameter5>
                    <parameter6>NOTIFY=silent</parameter6>
                    \(overrideParameters)
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
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw PolicyCreationError.networkFailure(urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolicyCreationError.networkFailure("Jamf returned an unreadable response.")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            // Developer-facing only, and deliberately status-code-only: the response body can echo
            // tenant data, so it is classified below and then discarded rather than logged.
            print("[Installomator] Policy creation rejected by Jamf (HTTP \(httpResponse.statusCode))")

            throw Self.creationFailure(
                status: httpResponse.statusCode,
                body: data,
                policyName: policyName,
                categoryName: categoryName
            )
        }

        // The policy now exists in Jamf. Read its id back so the caller can attach an icon — using
        // `try?` because failing to parse the id must never be reported as a failed creation.
        return try? parseIDFromXMLResponse(data: data, elementName: "id")
    }

    /// Resolves a policy name from the template. Lives on `InstallomatorOverrides` so the rule is
    /// pure value logic that can be exercised on its own; this is the call site's shorthand.
    static func resolvePolicyName(template: String, appName: String, version: String?) -> String {
        InstallomatorOverrides.policyName(template: template, appName: appName, version: version)
    }

    // MARK: - Failure Classification

    /// Turns a non-2xx Jamf response into an actionable error.
    ///
    /// The body is inspected in memory for the few markers Jamf actually uses, reduced to a
    /// `JamfRejectionHint`, and then dropped — nothing from it reaches the error, the UI or a log.
    private static func creationFailure(
        status: Int,
        body: Data,
        policyName: String,
        categoryName: String
    ) -> PolicyCreationError {
        // The status code is authoritative for auth, throttling and server faults; the body is only
        // consulted for 400/409, where Jamf uses the same code for genuinely different problems.
        switch status {
        case 400, 409:
            switch rejectionHint(from: body) {
            case .duplicateName:
                return .duplicateName(policyName)
            case .category:
                return .categoryRejected(categoryName)
            case .malformedBody:
                return .malformedRequest
            case .none:
                // A terse 409 on policy creation is nearly always a name clash; a terse 400 is a
                // body Jamf could not read.
                return status == 409 ? .duplicateName(policyName) : .malformedRequest
            }
        case 401:
            return .unauthorised
        case 403:
            return .insufficientPrivileges
        case 404:
            return .notFound
        case 429:
            return .rateLimited
        case 500...599:
            return .serverFailure(status)
        default:
            return .unexpectedResponse(status)
        }
    }

    /// Reduces a Jamf error body to a hint, without retaining any of its text.
    private static func rejectionHint(from body: Data) -> JamfRejectionHint {
        guard let raw = String(data: body, encoding: .utf8) else { return .none }
        let text = String(raw.prefix(4_096)).lowercased()

        if text.contains("duplicate") { return .duplicateName }
        if text.contains("category") { return .category }
        if text.contains("xml") || text.contains("parse") || text.contains("malformed") { return .malformedBody }
        return .none
    }
}
