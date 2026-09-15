//
//  JamfAPIService+PackageEditing.swift
//  JamfCommander
//
//  In-place editing of a deployed Installomator install policy: its name, enabled state, category,
//  Self Service presentation and icon, scope, and the Installomator label and argument overrides it
//  runs with.
//
//  Writes are Classic-API PUTs to `JSSResource/policies/id/{id}` carrying **only** the sections being
//  changed. Classic merges the sections a body supplies and leaves the rest of the policy alone — the
//  behaviour `movePolicy` and `assignPolicyIcon` already depend on — so changing a category can never
//  disturb a scope that was built by hand in Jamf.
//
//  `<scripts>` is the exception: supplying it replaces the whole list. Every script on the policy is
//  therefore written back, with only the Installomator entry's parameters rewritten, and the policy is
//  re-read immediately before the write so that list is the one Jamf holds now.
//
//  Every dynamic value is XML-escaped (root `CLAUDE.md`, invariant 3). These are writes to a live
//  production tenant: callers must confirm first and report the real per-policy outcome.
//

import Foundation

extension JamfAPIService {

    // MARK: - Edit value types

    /// The Installomator part of an edit: the label the policy runs and the argument overrides
    /// written to parameter7–parameter11.
    struct InstallomatorScriptEdit: Sendable {
        /// The id of the script entry on the policy that runs Installomator, resolved by the editor
        /// from the policy's own payload so an edit can never rewrite the wrong script.
        let scriptID: String
        /// Written to parameter4.
        let label: String
        /// Resolved `key=value` strings, at most `InstallomatorOverrides.maximumOverrides`.
        let overrides: [String]
    }

    /// What an edit changes on one policy.
    ///
    /// Every property is optional, and `nil` means "leave that part of the policy exactly as it is".
    /// That is what lets a label's shared settings be applied to its sibling policies without
    /// touching the names and pinned versions that tell them apart.
    struct InstallomatorPolicyEdit: Sendable {
        /// The policy name. Jamf requires these to be unique, so it is only ever set for the policy
        /// actually being edited — never for siblings.
        var policyName: String?
        /// Whether the policy is enabled in Jamf.
        var enabled: Bool?
        /// Target category, written to `<general>` **and** to the Self Service category together, the
        /// way `movePolicy` does, so the admin console and Self Service never drift apart.
        var categoryID: Int?
        var categoryName: String?
        /// Self Service presentation, written alongside the category block.
        var featureOnMainPage: Bool?
        var displayInSelfServiceCategory: Bool?
        /// Whether to write the new name as the Self Service display name too. Only true when the
        /// policy is being renamed — otherwise a display name deliberately set to something else in
        /// Jamf would be silently overwritten.
        var updateSelfServiceDisplayName: Bool = false
        /// An icon already in Jamf's icon library. `nil` keeps whatever the policy has: the Classic
        /// API offers no proven way to clear an icon, so the editor offers keep and replace only.
        var iconID: Int?
        /// A complete replacement scope. `nil` keeps the policy's scope untouched, including the
        /// parts this app does not model (exclusions, limitations, buildings, departments).
        var scope: DeploymentScopeConfig?
        /// The label and overrides. `nil` leaves the policy's scripts untouched.
        var installomator: InstallomatorScriptEdit?

        /// Whether this edit would write anything at all.
        var isEmpty: Bool {
            policyName == nil && enabled == nil && categoryID == nil
                && featureOnMainPage == nil && displayInSelfServiceCategory == nil
                && iconID == nil && scope == nil && installomator == nil
        }
    }

    /// One policy and the edit to apply to it.
    struct InstallomatorPolicyEditJob: Sendable {
        let target: InstallomatorPolicyTarget
        let edit: InstallomatorPolicyEdit
    }

    /// Why an edit could not be written, phrased so an administrator can act on it.
    enum PackageEditError: LocalizedError {
        /// The script the edit was built against is no longer on the policy — it was changed in Jamf
        /// in the meantime. Rewriting the list anyway could strip the policy's real script.
        case installomatorScriptMissing
        /// Nothing was changed, so nothing was sent.
        case nothingToApply

        var errorDescription: String? {
            switch self {
            case .installomatorScriptMissing:
                return "This policy no longer runs the Installomator script it was read from — it may have been changed in Jamf since the list was loaded. Refresh the Packages list and try again."
            case .nothingToApply:
                return "Nothing was changed, so no update was sent to Jamf."
            }
        }
    }

    // MARK: - Write

    /// Applies one edit to one policy as a single PUT carrying only the sections being changed.
    func updateInstallomatorPolicy(id: Int, edit: InstallomatorPolicyEdit) async throws {
        guard !edit.isEmpty else { throw PackageEditError.nothingToApply }

        var sections: [String] = []

        // --- general: name, enabled state, category ---
        var general: [String] = []
        if let policyName = edit.policyName {
            general.append("<name>\(Self.xmlEscape(policyName))</name>")
        }
        if let enabled = edit.enabled {
            general.append("<enabled>\(enabled)</enabled>")
        }
        if let categoryID = edit.categoryID, let categoryName = edit.categoryName {
            general.append("<category><id>\(categoryID)</id><name>\(Self.xmlEscape(categoryName))</name></category>")
        }
        if !general.isEmpty {
            sections.append("<general>\n\(general.joined(separator: "\n"))\n</general>")
        }

        // --- self service: display name, featuring, category listing, icon ---
        var selfService: [String] = []
        if edit.updateSelfServiceDisplayName, let policyName = edit.policyName {
            selfService.append("<self_service_display_name>\(Self.xmlEscape(policyName))</self_service_display_name>")
        }
        if let featureOnMainPage = edit.featureOnMainPage {
            selfService.append("<feature_on_main_page>\(featureOnMainPage)</feature_on_main_page>")
        }
        if let categoryID = edit.categoryID, let categoryName = edit.categoryName {
            // Mirrors what the create flow writes: the Self Service listing follows the policy's
            // category, and "feature on main page" is expressed in both places.
            let displayIn = edit.displayInSelfServiceCategory ?? true
            let featureIn = edit.featureOnMainPage ?? false
            selfService.append("""
            <self_service_categories>
                <category>
                    <id>\(categoryID)</id>
                    <name>\(Self.xmlEscape(categoryName))</name>
                    <display_in>\(displayIn)</display_in>
                    <feature_in>\(featureIn)</feature_in>
                </category>
            </self_service_categories>
            """)
        }
        if let iconID = edit.iconID {
            selfService.append("<self_service_icon><id>\(iconID)</id></self_service_icon>")
        }
        if !selfService.isEmpty {
            sections.append("<self_service>\n\(selfService.joined(separator: "\n"))\n</self_service>")
        }

        // --- scope: a full replacement, only when one was asked for ---
        if let scope = edit.scope {
            sections.append(Self.replacementScopeXML(for: scope))
        }

        // --- scripts: label and overrides ---
        if let installomator = edit.installomator {
            // Re-read immediately before the write. The whole scripts list is about to be replaced,
            // so it must be the list Jamf holds now, not the one the dashboard loaded earlier.
            let detail = try await fetchPolicyDetail(id: id)
            let scripts = detail.scripts ?? []
            guard scripts.contains(where: { $0.id == installomator.scriptID }) else {
                throw PackageEditError.installomatorScriptMissing
            }
            sections.append(Self.scriptsXML(for: scripts, applying: installomator))
        }

        let xml = "<policy>\n\(sections.joined(separator: "\n"))\n</policy>"
        try await genericRequest(method: "PUT", endpoint: "JSSResource/policies/id/\(id)", body: xml)
    }

    /// Applies a set of edits — the policy being edited, plus optionally the other policies that run
    /// the same label — and reports one result per policy.
    ///
    /// Paced like every other bulk write here (batches of five, 0.5s between batches), and one
    /// refusal never stops the rest of the run.
    func applyInstallomatorPolicyEdits(_ jobs: [InstallomatorPolicyEditJob]) async -> [OperationResult] {
        var results: [OperationResult] = []
        let batchSize = 5
        let batches = stride(from: 0, to: jobs.count, by: batchSize).map {
            Array(jobs[$0..<min($0 + batchSize, jobs.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: OperationResult.self) { group in
                for job in batch {
                    group.addTask {
                        do {
                            try await self.updateInstallomatorPolicy(id: job.target.policyID, edit: job.edit)
                            return OperationResult(itemName: job.target.policyName, success: true, error: nil)
                        } catch {
                            return OperationResult(
                                itemName: job.target.policyName,
                                success: false,
                                error: Self.editFailureReason(for: error)
                            )
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

    // MARK: - XML builders

    /// Rebuilds a policy's `<scripts>` section with the Installomator entry's parameters replaced.
    ///
    /// Every script the policy runs is written back, because Classic replaces this section wholesale
    /// rather than merging it — sending only the Installomator entry would quietly strip the others
    /// from a policy that runs more than one.
    ///
    /// Parameters 7–11 are always written for the edited entry, empty where unused, so removing a
    /// version pin actually clears it instead of leaving the old value in place.
    private static func scriptsXML(for scripts: [PolicyScript], applying edit: InstallomatorScriptEdit) -> String {
        let entries = scripts.map { script -> String in
            var parameters: [String?]
            if script.id == edit.scriptID {
                let overrides = Array(edit.overrides.prefix(InstallomatorOverrides.maximumOverrides))
                // parameter4 is the label; 5 and 6 (DEBUG / NOTIFY) are the policy's own and are
                // carried across untouched.
                parameters = [edit.label, script.parameter5, script.parameter6]
                for index in 0..<InstallomatorOverrides.maximumOverrides {
                    parameters.append(index < overrides.count ? overrides[index] : "")
                }
            } else {
                parameters = [
                    script.parameter4, script.parameter5, script.parameter6, script.parameter7,
                    script.parameter8, script.parameter9, script.parameter10, script.parameter11,
                ]
            }

            let parameterXML = parameters.enumerated().compactMap { index, value -> String? in
                guard let value else { return nil }
                return "<parameter\(index + 4)>\(xmlEscape(value))</parameter\(index + 4)>"
            }.joined(separator: "\n            ")

            let priorityXML = script.priority.map { "<priority>\(xmlEscape($0))</priority>" } ?? ""

            return """
                <script>
                    <id>\(xmlEscape(script.id))</id>
                    \(priorityXML)
                    \(parameterXML)
                </script>
            """
        }
        return "<scripts>\n\(entries.joined(separator: "\n"))\n</scripts>"
    }

    /// Scope XML for an **edit**, which has to replace what is there rather than add to it.
    ///
    /// Deliberately not `DeploymentScopeConfig.toScopeXML()`: that builds the scope of a policy that
    /// does not exist yet, where an omitted `<computers/>` is empty anyway. On an existing policy the
    /// same omission would leave the previous targets in place and silently widen the scope, so both
    /// target lists are always written, empty where unused — the shape `setPolicyScopeToAllComputers`
    /// already uses.
    ///
    /// Exclusions, limitations, buildings and departments are **not** written, so anything configured
    /// in Jamf beyond what this app models survives the edit.
    private static func replacementScopeXML(for scope: DeploymentScopeConfig) -> String {
        switch scope.scopeType {
        case .allComputers:
            return """
            <scope>
                <all_computers>true</all_computers>
                <computers/>
                <computer_groups/>
            </scope>
            """
        case .specificComputers:
            let computers = scope.selectedComputerIDs
                .map { "<computer><id>\(xmlEscape($0))</id></computer>" }
                .joined(separator: "\n            ")
            return """
            <scope>
                <all_computers>false</all_computers>
                <computers>
                    \(computers)
                </computers>
                <computer_groups/>
            </scope>
            """
        case .smartComputerGroups, .staticComputerGroups:
            let groups = scope.selectedGroupIDs
                .map { "<computer_group><id>\($0)</id></computer_group>" }
                .joined(separator: "\n            ")
            return """
            <scope>
                <all_computers>false</all_computers>
                <computers/>
                <computer_groups>
                    \(groups)
                </computer_groups>
            </scope>
            """
        }
    }

    // MARK: - Failure classification

    /// A reason the administrator can act on. Carries nothing from the response body (root
    /// `CLAUDE.md`, invariant 4) — `genericRequest` reports a non-2xx without one, so the realistic
    /// causes are named instead.
    /// `nonisolated` because the batch calls it from inside a `TaskGroup`.
    nonisolated private static func editFailureReason(for error: Error) -> String {
        if let editError = error as? PackageEditError {
            return editError.errorDescription ?? "The update could not be applied."
        }
        if let urlError = error as? URLError {
            return "Could not reach Jamf: \(urlError.localizedDescription)"
        }
        return "Jamf refused this update. The policy name may already be taken, the category may have been removed, or this API client may not have the 'Update Policies' privilege — check the policy in Jamf."
    }
}
