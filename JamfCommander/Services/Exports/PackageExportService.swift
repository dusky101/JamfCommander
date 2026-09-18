//
//  PackageExportService.swift
//  JamfCommander
//
//  Package export: everything this Jamf instance can install, and whether anything installs it.
//
//  Two kinds of row share one file, told apart by the **Source** column, because they are genuinely
//  different things that an administrator nonetheless has to review together:
//
//  · **Uploaded PKG** — a record in Jamf's package library. "Attached to Policy" means at least one
//    policy lists it in `package_configuration`. A "No" here is the interesting case: a package
//    sitting in the library that nothing installs.
//  · **Installomator** — a policy that installs software by running the Installomator script against
//    a label, and so has no library record at all. These have no attachment question to answer — the
//    row *is* a policy — so "Attached to Policy" is always Yes, and the column that says whether it
//    will actually run is **Policy Enabled**.
//
//  A basic export in the sense of `exports.md`: synchronous, built from data the caller already holds.
//  The expensive part — `JamfAPIService.scanPolicyEstate` reading every policy — belongs to the view
//  that already ran it, so exporting never triggers a second pass over the tenant.
//

import Foundation

class PackageExportService {

    /// Column order is fixed and shared by both row kinds; a column that cannot apply to a row is
    /// left empty rather than filled with a placeholder that would sort or filter as data.
    private static let header = [
        "Source",
        "Name",
        "File Name",
        "Installomator Label",
        "Pinned Version",
        "Category",
        "Attached to Policy",
        "Policy Count",
        "Policies",
        "Policy Enabled",
        "Package ID",
        "Policy ID",
        "Cloud Transfer Status",
        "Notes",
    ]

    /// Builds the CSV.
    ///
    /// - Parameters:
    ///   - packages: Jamf's package library, as `fetchJamfPackages()` returns it.
    ///   - usage: Package id → the names of the policies installing it, from `scanPolicyEstate`.
    ///     A package id missing from this map is installed by nothing.
    ///   - installomator: The Installomator policies found by the same scan.
    ///   - categoryNames: Jamf category id → name, so library rows carry a readable category rather
    ///     than the bare id the package record holds.
    static func exportToCSV(
        packages: [JamfPackage],
        usage: [String: [String]],
        installomator: [JamfAPIService.InstallomatorPolicyInfo],
        categoryNames: [String: String]
    ) -> String {
        var rows: [[String]] = [header]

        // Library packages first, alphabetically, so the orphans sit together once the sheet is
        // sorted on "Attached to Policy".
        let sortedPackages = packages.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        for package in sortedPackages {
            let policies = usage[package.id] ?? []
            let category = package.categoryID.flatMap { categoryNames[$0] } ?? "Uncategorised"

            rows.append([
                "Uploaded PKG",
                package.displayName,
                package.fileName,
                "",
                "",
                category,
                policies.isEmpty ? "No" : "Yes",
                String(policies.count),
                policies.joined(separator: "; "),
                "",
                package.id,
                "",
                package.cloudTransferStatus ?? "",
                package.notes ?? "",
            ])
        }

        let sortedInstallomator = installomator.sorted {
            $0.policyName.localizedCaseInsensitiveCompare($1.policyName) == .orderedAscending
        }

        for info in sortedInstallomator {
            rows.append([
                "Installomator",
                info.policyName,
                "",
                info.label,
                info.pinnedVersion ?? "",
                info.categoryName ?? "Uncategorised",
                // An Installomator row is its own policy, so there is no separate attachment to
                // report. Whether it reaches a Mac is Policy Enabled's job, not this column's.
                "Yes",
                "1",
                info.policyName,
                info.enabled ? "Yes" : "No",
                "",
                String(info.policyID),
                "",
                "",
            ])
        }

        return rows
            .map { $0.map(ExportHelpers.escapeCSV).joined(separator: ",") }
            .joined(separator: "\n")
            + "\n"
    }
}
