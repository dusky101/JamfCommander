//
//  BulkSettingsModels.swift
//  JamfCommander
//
//  Value types for the bulk in-place settings editor: apply an execution frequency, a
//  templated custom trigger, and/or a Self Service category across several existing
//  policies at once. Reuses `CloneTemplate` (BulkCloneModels) for the slug/template.
//

import Foundation

/// Per-policy plan row for a bulk in-place edit. `customTrigger` is the resolved
/// (templated, possibly overridden) value, used only when `applyCustomTrigger` is set.
struct BulkSettingsPlanItem: Identifiable, Sendable, Hashable {
    let policyId: Int
    let policyName: String
    let customTrigger: String

    var id: Int { policyId }

    var trimmedCustomTrigger: String {
        customTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What to apply across the selected policies. Each field is independently optional so the
/// user can change just one thing (e.g. only the frequency) without touching the rest.
struct BulkSettingsConfig: Sendable {
    /// When set, every policy's execution frequency is set to this.
    let applyFrequency: PolicyFrequency?
    /// When true, every policy's custom trigger (`trigger_other`) is set to its plan value
    /// (an empty value clears the policy's custom trigger).
    let applyCustomTrigger: Bool
    /// When set, every policy's Self Service category is set to this (via
    /// `setPolicySelfServiceCategory`).
    let selfServiceCategoryID: Int?
    let selfServiceCategoryName: String?
    /// When true, every policy is unscoped in place (it will stop deploying).
    let removeScope: Bool
    /// When true, every policy is scoped to all computers in place. Mutually exclusive with
    /// `removeScope` (the editor only allows one of the two scope actions at a time).
    let scopeToAllComputers: Bool

    var hasAnyChange: Bool {
        applyFrequency != nil || applyCustomTrigger || selfServiceCategoryID != nil || removeScope || scopeToAllComputers
    }
}
