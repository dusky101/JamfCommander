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
}
