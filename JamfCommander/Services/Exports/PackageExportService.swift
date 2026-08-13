//
//  PackageExportService.swift
//  JamfCommander
//
//  Installomator deployment export

import Foundation

/// Exports the Installomator apps deployed in this tenant.
///
/// Deployed policies only — this answers "what do we install through Installomator", not "what could
/// we install". That deliberately keeps the export independent of GitHub: the available-label list is
/// the only thing that needs it, and an export should not fail because raw.githubusercontent.com is
/// unreachable.
class PackageExportService {

    private static let headers = [
        "Policy ID", "Policy Name", "Label", "Application", "Category", "Enabled", "Pinned Version"
    ]

    /// Build the CSV from an already-fetched scan.
    static func exportToCSV(policies: [JamfAPIService.InstallomatorPolicyInfo]) -> String {
        var csv = headers.joined(separator: ",") + "\n"

        // Sorted by the name shown in the Packages module, then by pinned version, so the several
        // rows a version-pinned app produces stay together and in a predictable order.
        let sorted = policies.sorted {
            let leftName = InstallomatorLabelFormatter.displayName(for: $0.label)
            let rightName = InstallomatorLabelFormatter.displayName(for: $1.label)
            if leftName.localizedCaseInsensitiveCompare(rightName) != .orderedSame {
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
            return ($0.pinnedVersion ?? "") < ($1.pinnedVersion ?? "")
        }

        for policy in sorted {
            let fields = [
                String(policy.policyID),
                policy.policyName,
                policy.label,
                InstallomatorLabelFormatter.displayName(for: policy.label),
                policy.categoryName ?? "Uncategorised",
                policy.enabled ? "Yes" : "No",
                // Blank rather than "Latest": an empty cell reads as "not pinned", where a word
                // implies a version was chosen.
                policy.pinnedVersion ?? ""
            ]
            csv += fields.map(ExportHelpers.escapeCSV).joined(separator: ",") + "\n"
        }

        return csv
    }

    /// Build the CSV from the rows the Packages module already has on screen.
    ///
    /// Preferred from that module: the items are in memory, so exporting costs nothing and cannot
    /// disagree with what is displayed. Only deployed rows are written — an available label has no
    /// policy, no category and no version to report.
    static func exportToCSV(items: [InstallomatorItem]) -> String {
        let policies = items.compactMap { item -> JamfAPIService.InstallomatorPolicyInfo? in
            guard item.isDeployed, let policyID = item.policyID else { return nil }
            return JamfAPIService.InstallomatorPolicyInfo(
                policyID: policyID,
                policyName: item.policyName ?? "",
                label: item.label,
                categoryName: item.categoryName,
                enabled: item.enabled,
                pinnedVersion: item.pinnedVersion
            )
        }
        return exportToCSV(policies: policies)
    }

    /// Async variant that discovers the deployed policies first.
    ///
    /// - Parameter preferredScriptID: the script last deployed with, so detection matches the
    ///   Packages module exactly.
    static func exportToCSV(
        api: JamfAPIService,
        preferredScriptID: String = ""
    ) async throws -> String {
        let policies = try await api.fetchDeployedInstallomatorPolicies(
            preferredScriptID: preferredScriptID
        )
        return exportToCSV(policies: policies)
    }
}
