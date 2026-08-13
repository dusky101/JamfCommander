//
//  ExportHelpers.swift
//  JamfCommander
//
//  Helper functions for export services

import Foundation

class ExportHelpers {

    /// Escape CSV fields (handle commas, quotes, newlines)
    nonisolated static func escapeCSV(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes and escape quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    /// A date as `YYYY-MM-DD` for CSV output, or an empty field when absent.
    ///
    /// Deliberately not the localised format the UI uses: an export goes into Excel and finance
    /// systems, where an unambiguous, sortable date matters more than a readable one.
    nonisolated static func isoDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return isoFormatter.string(from: date)
    }

    private nonisolated static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
