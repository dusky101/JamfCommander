//
//  JamfAPIService+PolicyEditing.swift
//  JamfCommander
//
//  Read/write of a policy's General (execution frequency + triggers) and Self Service
//  settings via the Classic API. Writes build explicit, XML-escaped `<policy>` bodies
//  (not regex surgery — that is kept only for transforming fetched payloads in
//  +Cloning) and PUT them to `JSSResource/policies/id/{id}`.
//
//  Every value interpolated into XML is escaped with `JamfAPIService.xmlEscape(_:)`
//  per the project's non-negotiable invariants. These are writes to a live production
//  Jamf tenant — callers must confirm before invoking and report real outcomes.
//

import Foundation

extension JamfAPIService {

    // MARK: - Read

    /// Fetches a policy and maps it to the clean, editable value type used by the form
    /// editor and the bulk-clone/templating flows. Reuses the throttled, retried
    /// `fetchPolicyDetail(id:)`.
    func fetchPolicyEditable(id: Int) async throws -> PolicyEditable {
        let detail = try await fetchPolicyDetail(id: id)
        return PolicyEditable(detail: detail)
    }

    // MARK: - Write: General (execution frequency + triggers)

    /// Updates a policy's execution frequency and the six standard event triggers plus
    /// the optional custom event trigger (`trigger_other`). Sends only the `<general>`
    /// elements it manages, leaving the rest of the policy untouched.
    func updatePolicyGeneral(id: Int, frequency: PolicyFrequency, triggers: PolicyTriggers) async throws {
        // Frequency is a controlled enum value, but escape it anyway for uniformity.
        let escapedFrequency = Self.xmlEscape(frequency.jamfValue)
        // The custom trigger is free user text — must be escaped, and trimmed so a
        // whitespace-only value clears the trigger rather than writing blanks.
        let escapedCustomTrigger = Self.xmlEscape(triggers.trimmedCustomTrigger)

        let xml = """
        <policy>
            <general>
                <frequency>\(escapedFrequency)</frequency>
                <trigger_checkin>\(triggers.checkin)</trigger_checkin>
                <trigger_enrollment_complete>\(triggers.enrollmentComplete)</trigger_enrollment_complete>
                <trigger_login>\(triggers.login)</trigger_login>
                <trigger_logout>\(triggers.logout)</trigger_logout>
                <trigger_network_state_changed>\(triggers.networkStateChanged)</trigger_network_state_changed>
                <trigger_startup>\(triggers.startup)</trigger_startup>
                <trigger_other>\(escapedCustomTrigger)</trigger_other>
            </general>
        </policy>
        """
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    // MARK: - Write: Self Service

    /// Replaces a policy's Self Service page settings (the full `<self_service>` block the
    /// editor manages): the enable flag, display name, button text, description, the
    /// "force users to view description" and "feature on main page" flags, the Self
    /// Service categories, and — when an existing icon id is supplied — the icon
    /// assignment. Uploading a new icon is a separate multipart endpoint handled in a
    /// later phase; this method only references an icon by id.
    func updatePolicySelfService(id: Int, settings: SelfServiceSettings) async throws {
        let categoriesXML: String
        if settings.categories.isEmpty {
            // Self-closing element clears the Self Service categories.
            categoriesXML = "<self_service_categories/>"
        } else {
            let inner = settings.categories.map { category in
                """
                <category>
                    <id>\(category.id)</id>
                    <name>\(Self.xmlEscape(category.name))</name>
                    <display_in>\(category.displayIn)</display_in>
                    <feature_in>\(category.featureIn)</feature_in>
                </category>
                """
            }.joined(separator: "\n")
            categoriesXML = "<self_service_categories>\n\(inner)\n</self_service_categories>"
        }

        // Only reference an icon when one is actually assigned (reuse-existing path).
        var iconXML = ""
        if let iconID = settings.icon?.id {
            iconXML = "<self_service_icon><id>\(iconID)</id></self_service_icon>"
        }

        let xml = """
        <policy>
            <self_service>
                <use_for_self_service>\(settings.useForSelfService)</use_for_self_service>
                <self_service_display_name>\(Self.xmlEscape(settings.displayName))</self_service_display_name>
                <install_button_text>\(Self.xmlEscape(settings.installButtonText))</install_button_text>
                <reinstall_button_text>\(Self.xmlEscape(settings.reinstallButtonText))</reinstall_button_text>
                <self_service_description>\(Self.xmlEscape(settings.description))</self_service_description>
                <force_users_to_view_description>\(settings.forceUsersToViewDescription)</force_users_to_view_description>
                <feature_on_main_page>\(settings.featureOnMainPage)</feature_on_main_page>
                \(categoriesXML)
                \(iconXML)
            </self_service>
        </policy>
        """
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    // MARK: - Bulk in-place settings

    /// Writes only the supplied `<general>` fields (a partial update) so other general
    /// fields aren't clobbered. A non-nil `customTrigger` writes `trigger_other` (an empty
    /// string clears it); nil skips it. Every dynamic value is XML-escaped.
    func updatePolicyGeneralFields(id: Int, frequency: PolicyFrequency?, customTrigger: String?) async throws {
        var elements = ""
        if let frequency {
            elements += "<frequency>\(Self.xmlEscape(frequency.jamfValue))</frequency>"
        }
        if let customTrigger {
            elements += "<trigger_other>\(Self.xmlEscape(customTrigger))</trigger_other>"
        }
        guard !elements.isEmpty else { return }
        let xml = "<policy><general>\(elements)</general></policy>"
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    /// Scopes a policy to all computers in place. Writes only the `<scope>` section, setting
    /// `all_computers` true and clearing any targeted computers/computer groups (mirrors the
    /// proven `setProfileScopeToAllComputers` shape). Existing exclusions are left untouched.
    func setPolicyScopeToAllComputers(id: Int) async throws {
        let xml = """
        <policy>
            <scope>
                <all_computers>true</all_computers>
                <computers/>
                <computer_groups/>
            </scope>
        </policy>
        """
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    /// Removes a policy's scope in place (unscopes it — it will no longer deploy). Writes
    /// only the `<scope>` section, using the same empty-scope shape proven in `clonePolicy`.
    func removePolicyScope(id: Int) async throws {
        let xml = """
        <policy>
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
        </policy>
        """
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    /// Applies the chosen settings (frequency / custom trigger / Self Service category) to
    /// each selected policy in place. Rate-limited (batches of 5 + 0.5s gaps); per-item
    /// failures are captured and the batch continues. Returns one `OperationResult` per
    /// item for `OperationResultView`.
    func bulkUpdatePolicySettings(_ items: [BulkSettingsPlanItem], config: BulkSettingsConfig) async -> [OperationResult] {
        var results: [OperationResult] = []
        let batchSize = 5
        let batches = stride(from: 0, to: items.count, by: batchSize).map {
            Array(items[$0..<min($0 + batchSize, items.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: OperationResult.self) { group in
                for item in batch {
                    group.addTask {
                        do {
                            // General: frequency and/or custom trigger (partial PUT).
                            if config.applyFrequency != nil || config.applyCustomTrigger {
                                let trigger: String? = config.applyCustomTrigger ? item.trimmedCustomTrigger : nil
                                try await self.updatePolicyGeneralFields(
                                    id: item.policyId,
                                    frequency: config.applyFrequency,
                                    customTrigger: trigger
                                )
                            }
                            // Self Service category (reuses the existing matcher method).
                            if let categoryID = config.selfServiceCategoryID, let categoryName = config.selfServiceCategoryName {
                                try await self.setPolicySelfServiceCategory(id: item.policyId, toCategoryID: categoryID, categoryName: categoryName)
                            }
                            // Scope action (mutually exclusive in the editor): scope to all
                            // computers, or remove scope entirely.
                            if config.scopeToAllComputers {
                                try await self.setPolicyScopeToAllComputers(id: item.policyId)
                            } else if config.removeScope {
                                try await self.removePolicyScope(id: item.policyId)
                            }
                            return OperationResult(itemName: item.policyName, success: true, error: nil)
                        } catch {
                            return OperationResult(itemName: item.policyName, success: false, error: "\(error)")
                        }
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
}
