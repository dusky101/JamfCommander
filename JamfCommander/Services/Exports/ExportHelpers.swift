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
}
