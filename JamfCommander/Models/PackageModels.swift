//
//  PackageModels.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Data Structures

struct InstallomatorLabel: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

struct IntuneApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let platform: String // "macOS" or "Windows"
    let rawRow: String
}

struct PackageMatch: Identifiable, Hashable {
    let id = UUID()
    let intuneApp: IntuneApp
    let matchedLabel: String
    var isSelected: Bool = false
    
    var matchType: String {
        return "Fuzzy Match"
    }
    
    // Helper for the UI to show the correct icon
    var platformIcon: String {
        return intuneApp.platform.lowercased().contains("mac") ? "applelogo" : "desktopcomputer"
    }
}

// Unified display item that can represent either a matched package or a standalone label
struct PackageDisplayItem: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let matchedApp: IntuneApp?
    
    var isMatched: Bool {
        return matchedApp != nil
    }
    
    var displayName: String {
        return matchedApp?.name ?? label
    }
    
    var platform: String {
        return matchedApp?.platform ?? "Installomator"
    }
    
    var platformIcon: String {
        if let app = matchedApp {
            return app.platform.lowercased().contains("mac") ? "applelogo" : "desktopcomputer"
        }
        return "tag.fill"
    }
}

// MARK: - Package Matching Logic

class PackageMatchingService: ObservableObject {
    @Published var matches: [PackageMatch] = []
    @Published var isProcessing: Bool = false
    
    // Import Status
    @Published var labelsFileName: String? = nil
    @Published var macAppsFileName: String? = nil
    @Published var pcAppsFileName: String? = nil
    
    // Internal Data
    private var labels: [String] = []
    private var macApps: [IntuneApp] = []
    private var pcApps: [IntuneApp] = []
    
    // Expose all labels for "show all" mode
    var allLabels: [String] {
        return labels.sorted()
    }
    
    // Persistence File Names
    private let savedLabelsName = "Commander_Saved_Labels.txt"
    private let savedMacName = "Commander_Saved_MacApps.csv"
    private let savedPCName = "Commander_Saved_PCApps.csv"
    
    static let shared = PackageMatchingService()
    
    // MARK: - Initialization (Auto-Load)
    
    init() {
        loadPersistedData()
    }
    
    // MARK: - Persistence Logic
    
    private func getDocumentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    private func saveToDocuments(content: String, filename: String) {
        guard let url = getDocumentsDirectory()?.appendingPathComponent(filename) else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("Saved \(filename) to Documents.")
        } catch {
            print("Failed to save \(filename): \(error.localizedDescription)")
        }
    }
    
    private func loadPersistedData() {
        guard let docDir = getDocumentsDirectory() else { return }
        
        // 1. Load Labels
        let labelsURL = docDir.appendingPathComponent(savedLabelsName)
        if let content = try? String(contentsOf: labelsURL, encoding: .utf8) {
            self.labels = processLabelContent(content)
            self.labelsFileName = "Saved Labels.txt"
        }
        
        // 2. Load Mac Apps
        let macURL = docDir.appendingPathComponent(savedMacName)
        if let content = try? String(contentsOf: macURL, encoding: .utf8) {
            self.macApps = parseCSV(content: content)
            self.macAppsFileName = "Saved MacApps.csv"
        }
        
        // 3. Load PC Apps
        let pcURL = docDir.appendingPathComponent(savedPCName)
        if let content = try? String(contentsOf: pcURL, encoding: .utf8) {
            self.pcApps = parseCSV(content: content)
            self.pcAppsFileName = "Saved PCApps.csv"
        }
    }
    
    // MARK: - Import Methods
    
    func reset() {
        self.matches = []
        // We do not clear the files here so they persist for the session
    }
    
    func loadLabels(from url: URL) {
        guard let content = readFileContent(from: url) else { return }
        
        self.labels = processLabelContent(content)
        self.labelsFileName = url.lastPathComponent
        
        saveToDocuments(content: content, filename: savedLabelsName)
    }
    
    func loadMacCSV(from url: URL) {
        guard let content = readFileContent(from: url) else { return }
        self.macApps = parseCSV(content: content)
        self.macAppsFileName = url.lastPathComponent
        
        saveToDocuments(content: content, filename: savedMacName)
    }
    
    func loadPCCSV(from url: URL) {
        guard let content = readFileContent(from: url) else { return }
        self.pcApps = parseCSV(content: content)
        self.pcAppsFileName = url.lastPathComponent
        
        saveToDocuments(content: content, filename: savedPCName)
    }
    
    /// Helper to safely read file content including Security Scoped resources
    private func readFileContent(from url: URL) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Failed to read file: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func processLabelContent(_ content: String) -> [String] {
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Processing
    
    func processMatches() {
        guard !labels.isEmpty, (!macApps.isEmpty || !pcApps.isEmpty) else { return }
        
        self.isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Combine apps: Mac First, then PC.
            // This order is critical for the "Mac Wins" logic in findMatches.
            let allApps = self.macApps + self.pcApps
            let foundMatches = self.findMatches(apps: allApps, labels: self.labels)
            
            DispatchQueue.main.async {
                self.matches = foundMatches
                self.isProcessing = false
            }
        }
    }
    
    private func parseCSV(content: String) -> [IntuneApp] {
        var apps: [IntuneApp] = []
        let rows = content.components(separatedBy: .newlines)
        
        for (index, row) in rows.enumerated() {
            if index == 0 { continue } // Skip header
            
            let columns = row.components(separatedBy: ",")
            if columns.count >= 2 {
                let name = columns[0].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                let platform = columns[1].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                
                // We accept ALL rows (no filtering by type or platform)
                if !name.isEmpty {
                    apps.append(IntuneApp(name: name, platform: platform, rawRow: row))
                }
            }
        }
        return apps
    }
    
    // MARK: - Matching Algorithm
    
    private func findMatches(apps: [IntuneApp], labels: [String]) -> [PackageMatch] {
        var results: [PackageMatch] = []
        
        // Track which LABELS have been matched.
        // If "Zoom" (Mac) matches "zoomclient", we add "zoomclient" to this set.
        // If "Zoom Client" (PC) matches "zoomclient" later, we see it's in the set and skip the PC version.
        var seenLabels = Set<String>()
        
        for app in apps {
            // Normalization
            let normalizedAppName = app.name.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: ".", with: "")
            
            var matchFound: String?
            
            // Strategy 1: Exact Match (Fastest)
            if let exactMatch = labels.first(where: { $0 == normalizedAppName }) {
                matchFound = exactMatch
            }
            // Strategy 2: Clever Match (Longest matching label wins)
            // Example: "zoomclientforwindows" contains "zoom" (len 4) and "zoomclient" (len 10).
            // We want "zoomclient".
            else {
                // Find ALL labels that are contained inside the app name
                let potentialMatches = labels.filter { label in
                    normalizedAppName.contains(label)
                }
                
                // Sort by length (descending) and pick the longest one
                if let bestMatch = potentialMatches.max(by: { $0.count < $1.count }) {
                    matchFound = bestMatch
                }
            }
            
            // Success & De-duplication
            if let label = matchFound {
                // Mac Wins Logic:
                // Because 'apps' is ordered [MacApps, PCApps], matches found here are strictly in that order.
                // If we have already seen this Label, it means a Mac app (or an earlier PC app) claimed it.
                if !seenLabels.contains(label) {
                    results.append(PackageMatch(intuneApp: app, matchedLabel: label))
                    seenLabels.insert(label)
                }
            }
        }
        
        // Sort results: Mac apps first, then alphabetical by name
        return results.sorted {
            if $0.intuneApp.platform == $1.intuneApp.platform {
                return $0.intuneApp.name < $1.intuneApp.name
            }
            return $0.intuneApp.platform < $1.intuneApp.platform
        }
    }
}
