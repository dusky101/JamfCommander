//
//  RedundantModels.swift
//  JamfCommander
//
//  The Redundant audit: Jamf objects that look like they do nothing.
//
//  "Redundant" is a judgement, so the rules behind it are written down here rather than buried in a
//  view, and every row carries the reason it was listed:
//
//  · A **policy** is listed when it is disabled, or when nothing is scoped to it. Either way it
//    installs nothing today — but the two are very different in intent, which is why they are
//    separate reasons and never merged into one "redundant" flag.
//  · A **profile** is listed only when nothing is scoped to it. Jamf configuration profiles have no
//    enabled/disabled flag at all, so "not enabled" can never apply to one. The app does not invent
//    a state Jamf does not have.
//  · A **package** is listed when no policy installs it. It is reported, never acted on — see
//    `RedundantKind.supportsActions`.
//
//  IMPORTANT — what "not scoped" means here. It is read from the scope fields this app decodes:
//  `all_computers`, targeted computers, and targeted computer groups. Jamf can also scope by
//  building, department or user, and `PolicyScope`/`ScopeInfo` do not model those, so a policy
//  scoped *only* that way would be listed as unscoped when it is not. The UI says so in as many
//  words, and this is why the audit reports rather than acts on its own.
//

import Foundation
import SwiftUI

// MARK: - Why an item is listed

/// The reason an object appears in the audit. An object can have more than one.
enum RedundantReason: String, CaseIterable, Identifiable, Sendable {
    /// A policy Jamf holds but will not run.
    case notEnabled = "Not enabled"
    /// Nothing is scoped to it, so it reaches no Mac.
    case notScoped = "Not scoped"
    /// A package in Jamf's library that no policy installs.
    case notAttached = "Not attached"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notEnabled: return "pause.circle"
        case .notScoped: return "target"
        case .notAttached: return "shippingbox"
        }
    }

    var colour: Color {
        switch self {
        case .notEnabled: return .orange
        case .notScoped: return .purple
        case .notAttached: return .teal
        }
    }

    /// Spelled out for the row, because the short label alone invites the wrong conclusion.
    var explanation: String {
        switch self {
        case .notEnabled:
            return "Disabled in Jamf, so it will not run."
        case .notScoped:
            return "No computers or computer groups are targeted, so it reaches no Mac."
        case .notAttached:
            return "No policy installs this package."
        }
    }
}

// MARK: - What kind of object a row is

enum RedundantKind: String, CaseIterable, Identifiable, Sendable {
    case policy = "Policies"
    case profile = "Profiles"
    case package = "Packages"

    var id: String { rawValue }

    /// For a single row's label, where the plural section title would read wrongly.
    var singular: String {
        switch self {
        case .policy: return "Policy"
        case .profile: return "Profile"
        case .package: return "Package"
        }
    }

    var icon: String {
        switch self {
        case .policy: return "scroll.fill"
        case .profile: return "doc.text.fill"
        case .package: return "shippingbox.fill"
        }
    }

    var colour: Color {
        switch self {
        case .policy: return .purple
        case .profile: return .orange
        case .package: return .indigo
        }
    }

    /// Whether the audit offers to change objects of this kind.
    ///
    /// Packages are reported only. Removing a package record is a different and heavier act than
    /// deleting a policy — `JamfAPIService.deletePackageRecord` exists solely to clean up a record
    /// this app created moments earlier and could not upload to, and is deliberately not offered as
    /// a general way to remove packages.
    var supportsActions: Bool {
        self != .package
    }
}

// MARK: - A row

/// One object in the audit, flattened from whichever Jamf type it came from so three kinds can share
/// a list, a selection and a set of actions.
struct RedundantItem: Identifiable, Hashable, Sendable {
    let kind: RedundantKind
    /// The object's own Jamf id, as its API returns it — Classic ids are integers, Pro package ids
    /// are strings, so this keeps the string form and `numericID` converts where a write needs it.
    let jamfID: String
    let name: String
    let categoryName: String
    /// Every reason this item is listed; a policy can be both disabled and unscoped.
    let reasons: Set<RedundantReason>
    /// Policies only. `nil` for profiles (Jamf gives them no such flag) and packages.
    let isEnabled: Bool?
    /// Policies only: this policy installs through Installomator. Worth knowing before deleting it,
    /// because the software it installs has no package in the library to fall back on.
    let isInstallomator: Bool

    /// Unique across kinds: a policy and a profile can hold the same integer id.
    var id: String { "\(kind.rawValue)-\(jamfID)" }

    /// The id in the form the Classic API writes take. `nil` for a package id that is not an integer.
    var numericID: Int? { Int(jamfID) }

    /// Whether this row can be disabled — it must be a policy, and already enabled.
    var canBeDisabled: Bool {
        kind == .policy && isEnabled == true
    }

    /// Reasons in a stable order, so a row's badges do not reshuffle between scans.
    var orderedReasons: [RedundantReason] {
        RedundantReason.allCases.filter { reasons.contains($0) }
    }
}

// MARK: - Filtering

enum RedundantFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case notEnabled = "Not enabled"
    case notScoped = "Not scoped"
    case notAttached = "Not attached"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .notEnabled: return "pause.circle"
        case .notScoped: return "target"
        case .notAttached: return "shippingbox"
        }
    }

    /// The reason this filter selects, or `nil` for "All".
    var reason: RedundantReason? {
        switch self {
        case .all: return nil
        case .notEnabled: return .notEnabled
        case .notScoped: return .notScoped
        case .notAttached: return .notAttached
        }
    }

    func matches(_ item: RedundantItem) -> Bool {
        guard let reason else { return true }
        return item.reasons.contains(reason)
    }
}

// MARK: - Building the audit

/// Turns what the scans returned into the audit list. Pure: no networking, no state, so the rules
/// above are the whole story and can be read in one place.
enum RedundantAudit {

    /// Whether a policy's scope reaches anything this app can see.
    ///
    /// Mirrors `ProfileDetail.isActive` deliberately, so a policy and a profile are judged by the
    /// same standard. See the file header for what this cannot see.
    static func isScoped(_ scope: PolicyScope?) -> Bool {
        guard let scope else { return false }
        if scope.all_computers { return true }
        let hasComputers = !(scope.computers?.isEmpty ?? true)
        let hasGroups = !(scope.computer_groups?.isEmpty ?? true)
        return hasComputers || hasGroups
    }

    /// Everything that looks redundant, sorted by kind and then name.
    ///
    /// - Parameters:
    ///   - policies: Every policy, hydrated with enabled state and scope.
    ///   - profiles: Every configuration profile, hydrated with its scope-derived `isActive`.
    ///   - packages: Jamf's package library.
    ///   - packageUsage: Package id → the policies installing it, from `scanPolicyEstate`.
    ///   - installomatorPolicyIDs: Ids of the policies that install through Installomator.
    ///   - categoryNames: Jamf category id → name, for package rows, whose record carries only an id.
    static func items(
        policies: [Policy],
        profiles: [ConfigProfile],
        packages: [JamfPackage],
        packageUsage: [String: [String]],
        installomatorPolicyIDs: Set<Int>,
        categoryNames: [String: String]
    ) -> [RedundantItem] {
        var items: [RedundantItem] = []

        for policy in policies {
            var reasons: Set<RedundantReason> = []
            if !policy.enabled { reasons.insert(.notEnabled) }
            if !isScoped(policy.scope) { reasons.insert(.notScoped) }
            guard !reasons.isEmpty else { continue }

            items.append(
                RedundantItem(
                    kind: .policy,
                    jamfID: String(policy.id),
                    name: policy.name,
                    categoryName: policy.categoryName ?? "Uncategorised",
                    reasons: reasons,
                    isEnabled: policy.enabled,
                    isInstallomator: installomatorPolicyIDs.contains(policy.id)
                )
            )
        }

        for profile in profiles where !profile.isActive {
            items.append(
                RedundantItem(
                    kind: .profile,
                    jamfID: String(profile.id),
                    name: profile.name,
                    categoryName: profile.categoryName,
                    // Jamf has no enabled flag for a configuration profile, so there is nothing
                    // truthful to put in `isEnabled`.
                    reasons: [.notScoped],
                    isEnabled: nil,
                    isInstallomator: false
                )
            )
        }

        for package in packages where (packageUsage[package.id] ?? []).isEmpty {
            items.append(
                RedundantItem(
                    kind: .package,
                    jamfID: package.id,
                    name: package.displayName,
                    categoryName: package.categoryID.flatMap { categoryNames[$0] } ?? "Uncategorised",
                    reasons: [.notAttached],
                    isEnabled: nil,
                    isInstallomator: false
                )
            )
        }

        let kindOrder = RedundantKind.allCases
        return items.sorted { lhs, rhs in
            let lhsKind = kindOrder.firstIndex(of: lhs.kind) ?? 0
            let rhsKind = kindOrder.firstIndex(of: rhs.kind) ?? 0
            if lhsKind != rhsKind { return lhsKind < rhsKind }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
