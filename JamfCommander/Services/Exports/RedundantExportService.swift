//
//  RedundantExportService.swift
//  JamfCommander
//
//  The Redundant audit as a CSV — the report you take to somebody else before anything is deleted.
//
//  Deliberately plain. Its job is to record what the audit found and why, in a form that survives
//  leaving the app: one row per object, the reasons spelled out rather than encoded, and the same
//  three kinds the view shows.
//
//  A basic export in the sense of `exports.md`: synchronous, built from the items the view already
//  holds, so producing the report never re-reads the tenant.
//

import Foundation

class RedundantExportService {

    private static let header = [
        "Type",
        "Name",
        "Jamf ID",
        "Category",
        "Reasons",
        "Enabled",
        "Installomator",
    ]

    /// Builds the CSV from the items given — the caller passes the filtered view, so the file
    /// matches what was on screen rather than quietly widening to the whole scan.
    static func exportToCSV(items: [RedundantItem]) -> String {
        var rows: [[String]] = [header]

        for item in items {
            rows.append([
                item.kind.singular,
                item.name,
                item.jamfID,
                item.categoryName,
                item.orderedReasons.map(\.rawValue).joined(separator: "; "),
                // Empty rather than "No" where Jamf has no such state to report: a profile is not a
                // disabled policy, and a package is not something that runs.
                item.isEnabled.map { $0 ? "Yes" : "No" } ?? "",
                item.isInstallomator ? "Yes" : "",
            ])
        }

        return rows
            .map { $0.map(ExportHelpers.escapeCSV).joined(separator: ",") }
            .joined(separator: "\n")
            + "\n"
    }
}
