//
//  PackageModels.swift
//  JamfCommander
//
//  Created by Marc Oliff on 20/01/2026.
//

import Foundation
import SwiftUI

// MARK: - Installomator Item

/// Represents a single Installomator label — either deployed in Jamf or available from GitHub
struct InstallomatorItem: Identifiable, Hashable {
    let label: String            // Raw label, e.g. "googlechrome"
    let displayName: String      // Human-readable, e.g. "Google Chrome"
    let isDeployed: Bool         // true = already exists as a Jamf policy
    let policyID: Int?           // Jamf policy ID (if deployed)
    let policyName: String?      // Jamf policy name (if deployed)
    let categoryName: String?    // Jamf category (if deployed)
    let enabled: Bool            // Policy enabled state (false for available items)

    /// An existing Jamf policy whose name matches this app even though no Installomator policy was
    /// detected for it — typically a hand-made install policy, or one using a script we don't
    /// recognise. A hint only: the item stays selectable, but creating it may collide on the name.
    let existingPolicyName: String?

    var id: String { label }

    var safeCategory: String {
        categoryName ?? "Uncategorised"
    }

    /// Not confirmed as an Installomator deployment, but something in Jamf already looks like it.
    var isPossiblyDeployed: Bool {
        !isDeployed && existingPolicyName != nil
    }

    var statusText: String {
        if isDeployed { return "Deployed" }
        return isPossiblyDeployed ? "Possibly Deployed" : "Available"
    }

    var statusColor: Color {
        if isDeployed { return .green }
        return isPossiblyDeployed ? .orange : .blue
    }

    var statusIcon: String {
        if isDeployed { return "checkmark.seal.fill" }
        return isPossiblyDeployed ? "exclamationmark.triangle.fill" : "plus.circle"
    }
}

// MARK: - Policy Name Matching

/// Policy-name comparison shared by the Installomator dashboard and the deployment sheet.
///
/// Two deliberately different strengths: an exact key that predicts a real Jamf rejection, and a
/// looser key used only to hint that an app may already be installed by some other policy.
enum PolicyNameMatching {

    /// Case- and padding-insensitive form used to predict a genuine name clash (Jamf requires
    /// unique policy names). Kept exact apart from case and surrounding whitespace so the pre-flight
    /// check never cries wolf.
    static func exactKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Looser form that additionally drops a leading "install ", so a hand-made policy called
    /// "Install Google Chrome" is recognised as covering the same app as the `googlechrome` label.
    /// Only ever used to flag an item as *possibly* deployed — never to block a deployment.
    static func appKey(_ name: String) -> String {
        var key = exactKey(name)
        let prefix = "install "
        if key.hasPrefix(prefix) {
            key.removeFirst(prefix.count)
            key = key.trimmingCharacters(in: .whitespaces)
        }
        return key
    }
}

// MARK: - View Mode

enum PackageViewMode: String, CaseIterable, Identifiable {
    case deployed = "Deployed"
    case available = "Available"
    case all = "All Labels"
    
    var id: String { rawValue }
}

// MARK: - Group Mode

enum PackageGroupMode: String, CaseIterable, Identifiable {
    case alphabetical = "A-Z"
    case category = "Category"
    
    var id: String { rawValue }
}

// MARK: - Label Display Name Formatter

/// Converts an Installomator label like "googlechrome" into "Google Chrome"
/// Uses a known overrides dictionary for common apps, with a heuristic fallback.
struct InstallomatorLabelFormatter {
    
    /// Known label -> display name overrides where the heuristic would fail.
    ///
    /// A handful of these labels (e.g. `adobeacrobatreader`, `microsoftteamsclassic`,
    /// `sublimetext4`) no longer exist upstream, and are **kept deliberately**: the Deployed list
    /// formats names from each policy's own `parameter4`, so a policy created against a retired
    /// label still needs a readable name. A miss here is a free dictionary lookup that falls
    /// through to the heuristic, so retaining them costs nothing.
    private static let knownOverrides: [String: String] = [
        // Google
        "googlechrome": "Google Chrome",
        "googlechromepkg": "Google Chrome (PKG)",
        "googledrive": "Google Drive",
        "googledrivefilestream": "Google Drive File Stream",
        "googleearth": "Google Earth",
        "googleearth7pro": "Google Earth 7 Pro",
        // Microsoft
        "microsoftteams": "Microsoft Teams",
        "microsoftteamsnew": "Microsoft Teams (New)",
        "microsoftteamsclassic": "Microsoft Teams Classic",
        "microsoftword": "Microsoft Word",
        "microsoftexcel": "Microsoft Excel",
        "microsoftpowerpoint": "Microsoft PowerPoint",
        "microsoftoutlook": "Microsoft Outlook",
        "microsoftonedrive": "Microsoft OneDrive",
        "microsoftedge": "Microsoft Edge",
        "microsoftdefender": "Microsoft Defender",
        "microsoftdefenderatp": "Microsoft Defender ATP",
        "microsoftremotedesktop": "Microsoft Remote Desktop",
        "microsoftcompanyportal": "Microsoft Company Portal",
        "microsoftskypeforbusiness": "Microsoft Skype for Business",
        "microsoftautoupdate": "Microsoft Auto Update",
        // Adobe
        "adobeacrobatprodc": "Adobe Acrobat Pro DC",
        "adobeacrobatreader": "Adobe Acrobat Reader",
        "adobecreativecloud": "Adobe Creative Cloud",
        "adobeconnect": "Adobe Connect",
        // Apple / Jamf
        "jamfconnect": "Jamf Connect",
        "jamfprotect": "Jamf Protect",
        "jamfmigrator": "Jamf Migrator",
        // Common Apps
        "1password7": "1Password 7",
        "1password8": "1Password 8",
        "1passwordcli": "1Password CLI",
        "firefox": "Firefox",
        "firefoxesr": "Firefox ESR",
        "firefoxesrpkg": "Firefox ESR (PKG)",
        "firefoxpkg": "Firefox (PKG)",
        "slack": "Slack",
        "zoom": "Zoom",
        "zoomclient": "Zoom Client",
        "zoomrooms": "Zoom Rooms",
        "spotify": "Spotify",
        "notion": "Notion",
        "figma": "Figma",
        "postman": "Postman",
        "docker": "Docker",
        "iterm2": "iTerm 2",
        "cyberduck": "Cyberduck",
        "handbrake": "HandBrake",
        "homebrew": "Homebrew",
        "vlc": "VLC",
        "gimp": "GIMP",
        "inkscape": "Inkscape",
        "brave": "Brave Browser",
        "bravebrowser": "Brave Browser",
        "sublimetext": "Sublime Text",
        "sublimetext4": "Sublime Text 4",
        "visualstudiocode": "Visual Studio Code",
        "vscodium": "VSCodium",
        "webex": "Webex",
        "whatsapp": "WhatsApp",
        "signal": "Signal",
        "telegram": "Telegram",
        "discord": "Discord",
        "skype": "Skype",
        "dropbox": "Dropbox",
        "evernote": "Evernote",
        "trello": "Trello",
        "obsidian": "Obsidian",
        "todoist": "Todoist",
        "grammarly": "Grammarly",
        "zotero": "Zotero",
        // Dev Tools
        "jetbrainsintellijidea": "JetBrains IntelliJ IDEA",
        "jetbrainspycharm": "JetBrains PyCharm",
        "jetbrainspycharmce": "JetBrains PyCharm CE",
        "jetbrainswebstorm": "JetBrains WebStorm",
        "jetbrainsphpstorm": "JetBrains PhpStorm",
        "jetbrainsgoland": "JetBrains GoLand",
        "jetbrainsclion": "JetBrains CLion",
        "jetbrainsrider": "JetBrains Rider",
        "jetbrainsdatagrip": "JetBrains DataGrip",
        "jetbrainstoolbox": "JetBrains Toolbox",
        // Utilities
        "appcleaner": "AppCleaner",
        "bartender": "Bartender",
        "bettertouchtool": "BetterTouchTool",
        "cleanmymac": "CleanMyMac",
        "rectangle": "Rectangle",
        "rectanglepro": "Rectangle Pro",
        "alfred": "Alfred",
        "raycast": "Raycast",
        "karabinerelements": "Karabiner-Elements",
        "keepassxc": "KeePassXC",
        "bitwarden": "Bitwarden",
    ]
    
    /// Main entry point: returns a human-readable name for a label
    static func displayName(for label: String) -> String {
        // 1. Check known overrides first
        if let override = knownOverrides[label.lowercased()] {
            return override
        }
        
        // 2. Apply heuristic: split on boundaries and capitalise
        return heuristicName(from: label)
    }
    
    /// Splits a label like "googlechrome" into words at camelCase / number boundaries
    /// then title-cases each word.
    private static func heuristicName(from label: String) -> String {
        var words: [String] = []
        var currentWord = ""
        let chars = Array(label)
        
        for i in 0..<chars.count {
            let char = chars[i]
            
            if i > 0 {
                let prev = chars[i - 1]
                var shouldSplit = false
                
                // Split: lowercase letter followed by uppercase letter
                if prev.isLowercase && char.isUppercase {
                    shouldSplit = true
                }
                // Split: letter followed by digit
                if prev.isLetter && char.isNumber {
                    shouldSplit = true
                }
                // Split: digit followed by letter
                if prev.isNumber && char.isLetter {
                    shouldSplit = true
                }
                
                if shouldSplit && !currentWord.isEmpty {
                    words.append(currentWord)
                    currentWord = ""
                }
            }
            
            currentWord.append(char)
        }
        
        if !currentWord.isEmpty {
            words.append(currentWord)
        }
        
        // Title-case each word
        return words.map { word in
            guard let first = word.first else { return word }
            return String(first).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
