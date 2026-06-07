//
//  ScriptExportService.swift
//  JamfCommander
//
//  Script export functionality

import Foundation

class ScriptExportService {

    /// Export scripts to CSV format
    /// Includes: ID, Name, Category, Priority, OS Requirements, Parameters (4-11), and Directories Created
    static func exportToCSV(scripts: [ScriptRecord]) -> String {
        var csv = "ID,Name,Category,Priority,OS Requirements,Info,Notes,Directories Created,Parameter 4,Parameter 5,Parameter 6,Parameter 7,Parameter 8,Parameter 9,Parameter 10,Parameter 11\n"

        for script in scripts.sorted(by: { $0.name < $1.name }) {
            let id = ExportHelpers.escapeCSV(script.id)
            let name = ExportHelpers.escapeCSV(script.name)
            let category = ExportHelpers.escapeCSV(script.categoryName ?? "Uncategorised")
            let priority = ExportHelpers.escapeCSV(script.priority ?? "")
            let osReqs = ExportHelpers.escapeCSV(script.osRequirements ?? "")
            let info = ExportHelpers.escapeCSV(script.info ?? "")
            let notes = ExportHelpers.escapeCSV(script.notes ?? "")

            // Extract directories from script content
            let directories = extractDirectoriesFromScript(script.scriptContents ?? "")
            let dirList = ExportHelpers.escapeCSV(directories.joined(separator: "; "))

            let p4 = ExportHelpers.escapeCSV(script.parameter4 ?? "")
            let p5 = ExportHelpers.escapeCSV(script.parameter5 ?? "")
            let p6 = ExportHelpers.escapeCSV(script.parameter6 ?? "")
            let p7 = ExportHelpers.escapeCSV(script.parameter7 ?? "")
            let p8 = ExportHelpers.escapeCSV(script.parameter8 ?? "")
            let p9 = ExportHelpers.escapeCSV(script.parameter9 ?? "")
            let p10 = ExportHelpers.escapeCSV(script.parameter10 ?? "")
            let p11 = ExportHelpers.escapeCSV(script.parameter11 ?? "")

            csv += "\(id),\(name),\(category),\(priority),\(osReqs),\(info),\(notes),\(dirList),\(p4),\(p5),\(p6),\(p7),\(p8),\(p9),\(p10),\(p11)\n"
        }

        return csv
    }

    /// Extracts directory paths from script content by scanning for mkdir commands
    /// Looks for patterns like: mkdir, mkdir -p, BASE_DIR="/path", ONBOARDING_DIR="${BASE_DIR}/subdir"
    private static func extractDirectoriesFromScript(_ scriptContent: String) -> [String] {
        var directories: [String] = []
        var variables: [String: String] = [:] // Track variable assignments

        let lines = scriptContent.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmedLine.hasPrefix("#") || trimmedLine.isEmpty {
                continue
            }

            // Extract variable assignments (e.g., BASE_DIR="/Library/Application Support")
            if let varMatch = extractVariableAssignment(from: trimmedLine) {
                variables[varMatch.name] = varMatch.value
            }

            // Look for mkdir commands
            if trimmedLine.contains("mkdir") {
                let dirs = extractDirectoriesFromMkdir(trimmedLine, variables: variables)
                directories.append(contentsOf: dirs)
            }
        }

        // Remove duplicates and sort
        return Array(Set(directories)).sorted()
    }

    /// Extracts variable assignments from a line (e.g., BASE_DIR="/path")
    private static func extractVariableAssignment(from line: String) -> (name: String, value: String)? {
        // Match patterns like: VARIABLE="/path" or VARIABLE="${OTHER_VAR}/subpath"
        let pattern = "^([A-Z_]+)=\"([^\"]+)\"$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard let nameRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let name = String(line[nameRange])
        let value = String(line[valueRange])

        // Resolve variable references (e.g., ${BASE_DIR}/subdir -> /Library/Application Support/subdir)
        // This is a simple implementation - could be enhanced for more complex cases

        return (name, value)
    }

    /// Extracts directory paths from mkdir commands
    private static func extractDirectoriesFromMkdir(_ line: String, variables: [String: String]) -> [String] {
        var directories: [String] = []

        // Use regex to extract quoted or unquoted paths after mkdir
        // Matches: mkdir -p "/path/with spaces" or mkdir -p /path or mkdir "$VAR"
        let patterns = [
            "mkdir\\s+(?:-[pm]\\s+)?[\"']([^\"']+)[\"']",  // Quoted paths: mkdir -p "/path/with spaces"
            "mkdir\\s+(?:-[pm]\\s+)?([^\\s\"']+)",         // Unquoted paths: mkdir -p /path
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))

            for match in matches {
                // Try to get the captured group (the path)
                let groupIndex = 1
                guard match.numberOfRanges > groupIndex else { continue }
                let capturedRange = match.range(at: groupIndex)
                guard let swiftRange = Range(capturedRange, in: line) else { continue }

                var dirPath = String(line[swiftRange])

                // Resolve variable references like $BASE_DIR or ${BASE_DIR}
                for (varName, varValue) in variables {
                    dirPath = dirPath
                        .replacingOccurrences(of: "${\(varName)}", with: varValue)
                        .replacingOccurrences(of: "$\(varName)", with: varValue)
                }

                // Only include if it looks like an absolute path and doesn't contain unresolved variables
                if dirPath.hasPrefix("/") && !dirPath.contains("$") {
                    directories.append(dirPath)
                    break  // Found a match, no need to try other patterns
                }
            }
        }

        return directories
    }
}
