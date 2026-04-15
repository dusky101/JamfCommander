//
//  SettingsService.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Service for importing and exporting Jamf Commander settings
/// Creates .jamfconfig files that can be shared between team members
struct SettingsService {
    
    // MARK: - Models
    
    struct JamfConfiguration: Codable {
        let instanceURL: String
        let clientId: String
        let clientSecret: String
        let exportDate: Date
        let appVersion: String
        let signature: String
        
        // Custom initializer for creating new configurations
        init(instanceURL: String, clientId: String, clientSecret: String, exportDate: Date, appVersion: String) {
            self.instanceURL = instanceURL
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.exportDate = exportDate
            self.appVersion = appVersion
            self.signature = "JamfCommander-v1"
        }
    }
    
    // MARK: - Export
    
    /// Export current settings to a .jamfconfig file
    /// - Parameters:
    ///   - instanceURL: The Jamf instance URL
    ///   - clientId: API Client ID
    ///   - clientSecret: API Client Secret
    /// - Returns: Success or failure
    static func exportSettings(instanceURL: String, clientId: String, clientSecret: String) -> Result<URL, SettingsError> {
        // Create configuration object
        let config = JamfConfiguration(
            instanceURL: instanceURL,
            clientId: clientId,
            clientSecret: clientSecret,
            exportDate: Date(),
            appVersion: "1.0.0" // You can make this dynamic later
        )
        
        // Encode to JSON
        guard let jsonData = try? JSONEncoder().encode(config) else {
            return .failure(.encodingFailed)
        }
        
        // Base64 encode for light obfuscation (makes it less human-readable)
        let encodedString = jsonData.base64EncodedString()
        
        // Add header to make it identifiable
        let fileContent = "JAMF_COMMANDER_CONFIG\n\(encodedString)"
        
        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Jamf Configuration"
        savePanel.message = "Save your Jamf connection settings to share with team members."
        savePanel.nameFieldStringValue = "JamfConfig-\(formatDate()).jamfconfig"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "jamfconfig") ?? .data]
        savePanel.canCreateDirectories = true
        
        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return .failure(.userCancelled)
        }
        
        // Write to file
        do {
            try fileContent.write(to: url, atomically: true, encoding: .utf8)
            return .success(url)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Import
    
    /// Import settings from a .jamfconfig file
    /// - Returns: Result with configuration or error
    static func importSettings() -> Result<JamfConfiguration, SettingsError> {
        // Create open panel
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Jamf Configuration"
        openPanel.message = "Select a .jamfconfig file to import settings."
        openPanel.allowedContentTypes = [UTType(filenameExtension: "jamfconfig") ?? .data]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        
        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return .failure(.userCancelled)
        }
        
        // Read file
        guard let fileContent = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure(.readFailed)
        }
        
        // Validate header
        let lines = fileContent.components(separatedBy: "\n")
        guard lines.count >= 2, lines[0] == "JAMF_COMMANDER_CONFIG" else {
            return .failure(.invalidFileFormat)
        }
        
        // Decode base64
        let encodedString = lines[1]
        guard let jsonData = Data(base64Encoded: encodedString) else {
            return .failure(.decodingFailed)
        }
        
        // Decode JSON
        do {
            let config = try JSONDecoder().decode(JamfConfiguration.self, from: jsonData)
            
            // Verify signature
            guard config.signature == "JamfCommander-v1" else {
                return .failure(.invalidSignature)
            }
            
            return .success(config)
        } catch {
            return .failure(.decodingFailed)
        }
    }
    
    // MARK: - Helpers
    
    private static func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    // MARK: - Error Types
    
    enum SettingsError: LocalizedError {
        case encodingFailed
        case decodingFailed
        case writeFailed(String)
        case readFailed
        case invalidFileFormat
        case invalidSignature
        case userCancelled
        
        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode configuration data."
            case .decodingFailed:
                return "Failed to decode configuration file. The file may be corrupted."
            case .writeFailed(let details):
                return "Failed to write configuration file: \(details)"
            case .readFailed:
                return "Failed to read configuration file."
            case .invalidFileFormat:
                return "Invalid file format. This doesn't appear to be a Jamf Commander configuration file."
            case .invalidSignature:
                return "Invalid file signature. This file may have been created by a different version."
            case .userCancelled:
                return "Operation cancelled by user."
            }
        }
    }
}
