//
//  PolicyEditingModels.swift
//  JamfCommander
//
//  Clean, UI-facing value types for editing a policy's General (frequency + triggers)
//  and Self Service settings. These are the types the form editor (Phase 2+) and the
//  bulk-clone/templating flows (Phase 4+) work against. They are populated from the
//  Classic-API decode layer (`PolicyDetailXML` / `PolicySelfServiceXML` in
//  PolicyModels.swift) and written back as escaped Classic XML by
//  `JamfAPIService+PolicyEditing.swift`.
//
//  All types are `Sendable` so they can cross actor / TaskGroup boundaries during the
//  rate-limited bulk operations.
//

import Foundation

// MARK: - Execution Frequency

/// A policy's execution frequency. Raw values are the exact strings Jamf expects in
/// `<general><frequency>` (Classic API). British English throughout.
enum PolicyFrequency: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case oncePerComputer = "Once per computer"
    case oncePerUserPerComputer = "Once per user per computer"
    case oncePerUser = "Once per user"
    case onceEveryDay = "Once every day"
    case onceEveryWeek = "Once every week"
    case onceEveryMonth = "Once every month"
    case ongoing = "Ongoing"

    var id: String { rawValue }

    /// The exact string Jamf expects in `<general><frequency>`.
    var jamfValue: String { rawValue }

    /// British English label shown in pickers and read-only summaries.
    var displayName: String {
        switch self {
        case .oncePerComputer: return "Once per computer"
        case .oncePerUserPerComputer: return "Once per user per computer"
        case .oncePerUser: return "Once per user"
        case .onceEveryDay: return "Once every day"
        case .onceEveryWeek: return "Once every week"
        case .onceEveryMonth: return "Once every month"
        case .ongoing: return "Ongoing"
        }
    }

    /// Jamf's default frequency for a new policy.
    static let `default`: PolicyFrequency = .oncePerComputer

    /// Defensive parse from a fetched frequency string. Trims whitespace and matches
    /// case-insensitively so minor formatting variance doesn't drop the value. Returns
    /// nil when the string is empty or unrecognised, so callers can decide the fallback.
    init?(jamfValue raw: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if let exact = PolicyFrequency(rawValue: trimmed) {
            self = exact
            return
        }
        let lowered = trimmed.lowercased()
        guard let match = PolicyFrequency.allCases.first(where: { $0.rawValue.lowercased() == lowered }) else {
            return nil
        }
        self = match
    }
}

// MARK: - Triggers

/// The six standard event triggers plus the optional custom event trigger
/// (`trigger_other`). These map directly to the Classic-API boolean elements
/// `trigger_checkin`, `trigger_enrollment_complete`, `trigger_login`, `trigger_logout`,
/// `trigger_network_state_changed`, `trigger_startup`, and the string `trigger_other`.
struct PolicyTriggers: Codable, Sendable, Hashable {
    var checkin: Bool              // trigger_checkin (Recurring Check-in)
    var enrollmentComplete: Bool   // trigger_enrollment_complete (Enrolment Complete)
    var login: Bool                // trigger_login (Login)
    var logout: Bool               // trigger_logout (Logout)
    var networkStateChanged: Bool  // trigger_network_state_changed (Network State Change)
    var startup: Bool              // trigger_startup (Startup)
    /// The optional custom event trigger (`trigger_other`). An empty string means none.
    var customTrigger: String

    init(checkin: Bool = false,
         enrollmentComplete: Bool = false,
         login: Bool = false,
         logout: Bool = false,
         networkStateChanged: Bool = false,
         startup: Bool = false,
         customTrigger: String = "") {
        self.checkin = checkin
        self.enrollmentComplete = enrollmentComplete
        self.login = login
        self.logout = logout
        self.networkStateChanged = networkStateChanged
        self.startup = startup
        self.customTrigger = customTrigger
    }

    /// No standard triggers and no custom trigger.
    static let none = PolicyTriggers()

    /// Builds the trigger set from a decoded `PolicyGeneral`, defaulting any missing
    /// boolean to false and a missing custom trigger to an empty string.
    init(general: PolicyGeneral) {
        self.init(
            checkin: general.trigger_checkin ?? false,
            enrollmentComplete: general.trigger_enrollment_complete ?? false,
            login: general.trigger_login ?? false,
            logout: general.trigger_logout ?? false,
            networkStateChanged: general.trigger_network_state_changed ?? false,
            startup: general.trigger_startup ?? false,
            customTrigger: general.trigger_other ?? ""
        )
    }

    /// The custom trigger with surrounding whitespace removed.
    var trimmedCustomTrigger: String {
        customTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCustomTrigger: Bool { !trimmedCustomTrigger.isEmpty }

    /// True when no standard event trigger and no custom trigger is set.
    var isEmpty: Bool {
        !checkin && !enrollmentComplete && !login && !logout
            && !networkStateChanged && !startup && !hasCustomTrigger
    }
}

// MARK: - Self Service

/// A single Self Service category assignment for a policy.
struct SelfServiceCategory: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    var name: String
    /// Whether the policy is listed under this category in Self Service (`display_in`).
    var displayIn: Bool
    /// Whether the policy is featured under this category (`feature_in`).
    var featureIn: Bool

    init(id: Int, name: String, displayIn: Bool = true, featureIn: Bool = false) {
        self.id = id
        self.name = name
        self.displayIn = displayIn
        self.featureIn = featureIn
    }
}

/// A reference to a Self Service icon. When reusing an existing Jamf icon only `id` is
/// required; `filename`/`uri` are informational (shown in the UI). Mirrors
/// `<self_service_icon>` (`id`/`filename`/`uri`).
struct SelfServiceIcon: Codable, Sendable, Hashable {
    var id: Int?
    var filename: String?
    var uri: String?

    init(id: Int? = nil, filename: String? = nil, uri: String? = nil) {
        self.id = id
        self.filename = filename
        self.uri = uri
    }

    /// An icon is "assigned" when Jamf has given it an id.
    var isAssigned: Bool { id != nil }

    /// Builds from the decode layer, treating an empty `<self_service_icon/>` (all-nil)
    /// as "no icon" so the UI doesn't show a phantom assignment.
    init?(xml: PolicySelfServiceIconXML?) {
        guard let xml else { return nil }
        let hasFilename = !(xml.filename ?? "").isEmpty
        let hasURI = !(xml.uri ?? "").isEmpty
        guard xml.id != nil || hasFilename || hasURI else { return nil }
        self.id = xml.id
        self.filename = xml.filename
        self.uri = xml.uri
    }
}

/// The full set of Self Service page settings the editor exposes. Defaults match Jamf's
/// defaults for a policy that is not surfaced in Self Service.
struct SelfServiceSettings: Codable, Sendable, Hashable {
    var useForSelfService: Bool
    var displayName: String
    var installButtonText: String
    var reinstallButtonText: String
    var description: String
    var forceUsersToViewDescription: Bool
    var featureOnMainPage: Bool
    var categories: [SelfServiceCategory]
    var icon: SelfServiceIcon?

    init(useForSelfService: Bool = false,
         displayName: String = "",
         installButtonText: String = "Install",
         reinstallButtonText: String = "Reinstall",
         description: String = "",
         forceUsersToViewDescription: Bool = false,
         featureOnMainPage: Bool = false,
         categories: [SelfServiceCategory] = [],
         icon: SelfServiceIcon? = nil) {
        self.useForSelfService = useForSelfService
        self.displayName = displayName
        self.installButtonText = installButtonText
        self.reinstallButtonText = reinstallButtonText
        self.description = description
        self.forceUsersToViewDescription = forceUsersToViewDescription
        self.featureOnMainPage = featureOnMainPage
        self.categories = categories
        self.icon = icon
    }

    /// A Self Service-disabled default.
    static let disabled = SelfServiceSettings()

    /// Builds clean settings from the decode layer, applying sensible British defaults for
    /// anything Jamf omitted.
    init(xml: PolicySelfServiceXML?) {
        guard let xml else {
            self = .disabled
            return
        }
        let cats: [SelfServiceCategory] = (xml.self_service_categories ?? []).compactMap { raw in
            guard let id = raw.id else { return nil }
            return SelfServiceCategory(
                id: id,
                name: raw.name ?? "",
                displayIn: raw.display_in ?? true,
                featureIn: raw.feature_in ?? false
            )
        }
        self.init(
            useForSelfService: xml.use_for_self_service ?? false,
            displayName: xml.self_service_display_name ?? "",
            installButtonText: xml.install_button_text ?? "Install",
            reinstallButtonText: xml.reinstall_button_text ?? "Reinstall",
            description: xml.self_service_description ?? "",
            forceUsersToViewDescription: xml.force_users_to_view_description ?? false,
            featureOnMainPage: xml.feature_on_main_page ?? false,
            categories: cats,
            icon: SelfServiceIcon(xml: xml.self_service_icon)
        )
    }
}

// MARK: - Aggregate editable policy

/// The editable view of a policy: identity plus the General (frequency + triggers) and
/// Self Service settings the new editor manages. Built from a fetched `PolicyDetailXML`
/// via `JamfAPIService.fetchPolicyEditable(id:)`.
struct PolicyEditable: Identifiable, Sendable, Hashable {
    let id: Int
    let name: String
    let enabled: Bool
    let categoryId: Int?
    let categoryName: String?
    var frequency: PolicyFrequency
    var triggers: PolicyTriggers
    var selfService: SelfServiceSettings

    init(detail: PolicyDetailXML) {
        self.id = detail.general.id
        self.name = detail.general.name
        self.enabled = detail.general.enabled
        self.categoryId = detail.general.category?.id
        self.categoryName = detail.general.category?.name
        self.frequency = PolicyFrequency(jamfValue: detail.general.frequency) ?? .default
        self.triggers = PolicyTriggers(general: detail.general)
        self.selfService = SelfServiceSettings(xml: detail.self_service)
    }
}
