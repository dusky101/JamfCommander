//
//  BulkCloneModels.swift
//  JamfCommander
//
//  Value types and templating helpers for multi-select bulk cloning of policies:
//  a per-row plan (resolved new name + custom trigger) and the shared configuration
//  (target category, safety strips, optional frequency to apply). Pure, `Sendable`
//  types so they can cross the rate-limited batch's TaskGroup boundary.
//

import Foundation

/// Per-policy plan for a bulk clone: the resolved new name and the (possibly overridden,
/// possibly empty) custom trigger to apply to the clone.
struct BulkClonePlanItem: Identifiable, Sendable, Hashable {
    let policyId: Int
    let originalName: String
    let newName: String
    let customTrigger: String

    var id: Int { policyId }

    /// `nonisolated` so it can be read from the off-main `withTaskGroup` clone runner (with
    /// main-actor-by-default isolation enabled via Approachable Concurrency, the struct is
    /// otherwise inferred `@MainActor`). Safe: it only trims an immutable `let` String.
    nonisolated var trimmedCustomTrigger: String {
        customTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Shared configuration for a bulk clone (everything that isn't per-row).
struct BulkCloneConfig: Sendable {
    let targetCategoryID: Int
    let targetCategoryName: String
    let stripScope: Bool
    let stripTriggers: Bool
    let stripFrequency: Bool
    let disableSelfService: Bool
    /// When set, every clone's execution frequency is set to this; nil leaves whatever the
    /// clone inherited (or the stripped default).
    let applyFrequency: PolicyFrequency?
}

/// Naming and custom-trigger templating helpers for bulk clone.
enum CloneTemplate {

    /// Builds a clone name as prefix + original + suffix. The caller guarantees at least
    /// one of prefix/suffix is non-empty so clones get unique names.
    static func newName(prefix: String, original: String, suffix: String) -> String {
        prefix + original + suffix
    }

    /// The custom-trigger token derived from a policy/app name: a leading verb
    /// (Install/Uninstall/…) is dropped, then the remainder is slugified. e.g.
    /// "Install Microsoft Word" → "microsoft-word".
    static func appNameToken(from policyName: String) -> String {
        var working = policyName
        let lower = working.lowercased()
        for verb in ["install ", "uninstall ", "reinstall ", "deploy ", "update ", "remove "] {
            if lower.hasPrefix(verb) {
                working = String(working.dropFirst(verb.count))
                break
            }
        }
        return slugify(working)
    }

    /// Lower-cases, turns any run of non-alphanumerics into a single hyphen, and trims
    /// leading/trailing hyphens. ASCII a–z / 0–9 only — safe for a Jamf custom event.
    static func slugify(_ input: String) -> String {
        var result = ""
        var pendingHyphen = false
        for scalar in input.lowercased().unicodeScalars {
            let isLowerAlpha = scalar >= "a" && scalar <= "z"
            let isDigit = scalar >= "0" && scalar <= "9"
            if isLowerAlpha || isDigit {
                if pendingHyphen && !result.isEmpty { result.append("-") }
                pendingHyphen = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        return result
    }

    /// Substitutes the `{appName}` token in a trigger template with the slugified app name.
    /// An empty template yields an empty trigger (no custom trigger).
    static func applyTriggerTemplate(_ template: String, policyName: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let token = appNameToken(from: policyName)
        return trimmed.replacingOccurrences(of: "{appName}", with: token)
    }
}
