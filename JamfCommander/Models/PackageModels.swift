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

    /// The version this policy pins, if any — read back from its `appNewVersion=` override. Several
    /// deployed rows can share one label precisely because each pins a different version.
    let pinnedVersion: String?

    /// An existing Jamf policy whose name matches this app even though no Installomator policy was
    /// detected for it — typically a hand-made install policy, or one using a script we don't
    /// recognise. A hint only: the item stays selectable, but creating it may collide on the name.
    let existingPolicyName: String?

    /// Whether this row's label still appears in the upstream Installomator label list.
    ///
    /// Available rows are built *from* that list, so they are always `true`. A deployed row is built
    /// from a Jamf policy, and a policy outlives the label it was created against: a label that is
    /// later withdrawn upstream leaves a policy that still runs but that Installomator no longer
    /// recognises, so it fails on every Mac it reaches. Marking the row is the only warning an
    /// administrator gets.
    ///
    /// Callers must pass `true` when the upstream list could not be read, so an unreachable GitHub
    /// never reports a healthy estate as missing.
    let labelExistsUpstream: Bool

    /// Unique per row, not per label. Version pinning makes several policies share one label — three
    /// pinned Go versions are three deployed rows all labelled `golang` — so identifying a row by its
    /// label alone gave `ForEach` duplicate ids. Available rows keep the bare label, which is what
    /// selection is keyed on.
    var id: String {
        guard let policyID else { return label }
        return "\(label)#\(policyID)"
    }

    var safeCategory: String {
        categoryName ?? "Uncategorised"
    }

    /// Not confirmed as an Installomator deployment, but something in Jamf already looks like it.
    var isPossiblyDeployed: Bool {
        !isDeployed && existingPolicyName != nil
    }

    /// Deployed against a label Installomator no longer publishes. The policy is still in Jamf and
    /// still runs — it just cannot succeed — so this is the state that needs an administrator.
    var isMissingLabel: Bool {
        isDeployed && !labelExistsUpstream
    }

    var statusText: String {
        if isMissingLabel { return "Missing" }
        if isDeployed { return "Deployed" }
        return isPossiblyDeployed ? "Possibly Deployed" : "Available"
    }

    var statusColor: Color {
        if isMissingLabel { return .orange }
        if isDeployed { return .green }
        return isPossiblyDeployed ? .orange : .blue
    }

    var statusIcon: String {
        // Deliberately the inverse of the deployed seal, so a missing row reads as a failed
        // deployment rather than as the "might already exist" hint, which keeps the same amber.
        if isMissingLabel { return "xmark.seal.fill" }
        if isDeployed { return "checkmark.seal.fill" }
        return isPossiblyDeployed ? "exclamationmark.triangle.fill" : "plus.circle"
    }

    /// One sentence explaining the status, for the card's tooltip and its accessibility label —
    /// status is never carried by colour alone.
    var statusExplanation: String {
        if isMissingLabel {
            return "'\(label)' is no longer in the Installomator label list, so this policy will fail when it next runs. Point it at a current label, or remove it."
        }
        if isDeployed {
            return "A Jamf policy already installs this label."
        }
        if let existingPolicyName {
            return "Not deployed by Installomator, but '\(existingPolicyName)' in Jamf looks like the same application."
        }
        return "Available to deploy as a new Self Service policy."
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
    /// Deployed policies whose label has since been withdrawn upstream — the ones needing attention.
    case missing = "Missing"
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
        // Names the token splitter gets close to but not exactly right
        "expressvpn": "ExpressVPN",
        "mysqlworkbenchce": "MySQL Workbench CE",
    ]
    
    /// Product words and edition suffixes used to split all-lowercase labels, each mapped to its
    /// proper casing. Installomator labels are lowercase and unpunctuated (`mysqlworkbenchce`), so
    /// the camelCase heuristic below has nothing to work with and returns "Mysqlworkbenchce".
    ///
    /// Deliberately conservative: only vendor names, product nouns and edition suffixes, no generic
    /// English fragments. Short words such as "key", "note", "one" or "box" are **excluded on
    /// purpose** — they would let an unrelated label decompose by accident ("keynote" → "Key Note").
    ///
    /// To extend it safely, repeat the check that produced this table: run
    /// `displayName(for:)` over the full upstream `Labels.txt` before and after the change and read
    /// every name that moves. The current table was verified that way over all 1,224 labels — it
    /// improves 26 names and changes nothing else.
    private static let knownTokens: [String: String] = [
        // Vendors and brands
        "mysql": "MySQL", "oracle": "Oracle", "google": "Google", "microsoft": "Microsoft",
        "adobe": "Adobe", "apple": "Apple", "jamf": "Jamf", "mozilla": "Mozilla",
        "jetbrains": "JetBrains", "vmware": "VMware", "omnissa": "Omnissa", "cisco": "Cisco",
        "horizon": "Horizon",
        "citrix": "Citrix", "zoom": "Zoom", "slack": "Slack", "dropbox": "Dropbox",
        "github": "GitHub", "gitlab": "GitLab", "docker": "Docker", "python": "Python",
        "postgres": "Postgres", "mongodb": "MongoDB", "nvidia": "NVIDIA", "logitech": "Logitech",
        "sophos": "Sophos", "mcafee": "McAfee", "symantec": "Symantec", "crowdstrike": "CrowdStrike",
        "malwarebytes": "Malwarebytes", "teamviewer": "TeamViewer", "anydesk": "AnyDesk",
        "splashtop": "Splashtop", "parallels": "Parallels", "virtualbox": "VirtualBox",
        "tableau": "Tableau", "notion": "Notion", "figma": "Figma", "spotify": "Spotify",
        "webex": "Webex", "firefox": "Firefox", "thunderbird": "Thunderbird",
        "libreoffice": "LibreOffice", "openoffice": "OpenOffice", "onlyoffice": "ONLYOFFICE",
        "keepass": "KeePass", "bitwarden": "Bitwarden", "lastpass": "LastPass",
        "wireshark": "Wireshark", "handbrake": "HandBrake", "audacity": "Audacity",
        "blender": "Blender", "inkscape": "Inkscape", "zotero": "Zotero", "mendeley": "Mendeley",
        "grammarly": "Grammarly", "evernote": "Evernote", "todoist": "Todoist", "trello": "Trello",
        "asana": "Asana", "confluence": "Confluence", "bluejeans": "BlueJeans",
        "gotomeeting": "GoToMeeting", "ringcentral": "RingCentral", "nextcloud": "Nextcloud",
        "owncloud": "ownCloud", "veracrypt": "VeraCrypt", "cyberduck": "Cyberduck",
        "filezilla": "FileZilla", "sequel": "Sequel", "postman": "Postman", "insomnia": "Insomnia",
        "sourcetree": "Sourcetree",
        // Product nouns
        "workbench": "Workbench", "browser": "Browser", "client": "Client", "server": "Server",
        "desktop": "Desktop", "viewer": "Viewer", "player": "Player", "reader": "Reader",
        "writer": "Writer", "manager": "Manager", "monitor": "Monitor", "studio": "Studio",
        "tools": "Tools", "agent": "Agent", "connect": "Connect", "connector": "Connector",
        "drive": "Drive", "cloud": "Cloud", "backup": "Backup", "remote": "Remote",
        "printer": "Printer", "scanner": "Scanner", "editor": "Editor", "terminal": "Terminal",
        "installer": "Installer", "updater": "Updater", "launcher": "Launcher", "suite": "Suite",
        "console": "Console", "portal": "Portal", "gateway": "Gateway", "bridge": "Bridge",
        "recorder": "Recorder", "converter": "Converter", "cleaner": "Cleaner", "finder": "Finder",
        "keyboard": "Keyboard", "display": "Display", "camera": "Camera",
        // Editions and variants
        "community": "Community", "enterprise": "Enterprise", "professional": "Professional",
        "standard": "Standard", "premium": "Premium", "basic": "Basic", "express": "Express",
        "classic": "Classic", "nightly": "Nightly", "canary": "Canary", "beta": "Beta",
        "ce": "CE", "dc": "DC", "esr": "ESR", "pkg": "PKG", "lts": "LTS", "pro": "Pro",
        "cli": "CLI", "sdk": "SDK", "jdk": "JDK", "jre": "JRE", "ide": "IDE", "vpn": "VPN",
        "security": "Security", "protect": "Protect", "defender": "Defender",
        "antivirus": "Antivirus",

        // Added 20 September 2026, after `acroniscyberprotectconnectagent` came through as one
        // unbroken word. Adding vocabulary is the cheapest thing that improves this: the
        // all-or-nothing rule in `segmentedName(from:)` means a token that never matches costs
        // nothing, and a label only segments when *every* character is accounted for.
        //
        // A general English dictionary was measured as an alternative and is worse than useless —
        // it splits "microsoftteams" into "micros · oft · teams". Brand names are not dictionary
        // words. See `docs/roadmap/POLICY_NAME_SUGGESTIONS.md`.

        // Vendors and brands
        "a": "A", "acronis": "Acronis", "autodesk": "Autodesk", "veeam": "Veeam", "nessus": "Nessus",
        "tenable": "Tenable", "qualys": "Qualys", "rapid": "Rapid", "trellix": "Trellix",
        "kandji": "Kandji", "addigy": "Addigy", "munki": "Munki", "mosyle": "Mosyle",
        "nomad": "NoMAD", "privileges": "Privileges", "suspicious": "Suspicious",
        "package": "Package", "installomator": "Installomator", "autopkg": "AutoPkg",
        "atlassian": "Atlassian", "bitbucket": "Bitbucket", "jira": "Jira",
        "zscaler": "Zscaler", "netskope": "Netskope", "proofpoint": "Proofpoint",
        "mimecast": "Mimecast", "barracuda": "Barracuda", "fortinet": "Fortinet",
        "forticlient": "FortiClient", "paloalto": "Palo Alto", "globalprotect": "GlobalProtect",
        "openvpn": "OpenVPN", "wireguard": "WireGuard", "tunnelblick": "Tunnelblick",
        "tailscale": "Tailscale", "cloudflare": "Cloudflare", "duo": "Duo", "okta": "Okta",
        "onepassword": "1Password", "dashlane": "Dashlane", "nordpass": "NordPass",
        "obsidian": "Obsidian", "devonthink": "DEVONthink", "omnigraffle": "OmniGraffle",
        "omnifocus": "OmniFocus", "omnioutliner": "OmniOutliner", "scrivener": "Scrivener",
        "sketch": "Sketch", "affinity": "Affinity", "pixelmator": "Pixelmator",
        "lightroom": "Lightroom", "photoshop": "Photoshop", "illustrator": "Illustrator",
        "premiere": "Premiere", "acrobat": "Acrobat", "creative": "Creative",
        "vlc": "VLC", "obs": "OBS", "ffmpeg": "FFmpeg", "davinci": "DaVinci",
        "resolve": "Resolve", "reaper": "REAPER", "ableton": "Ableton", "audition": "Audition",
        "sublime": "Sublime", "atom": "Atom", "brackets": "Brackets", "nova": "Nova",
        "xcode": "Xcode", "android": "Android", "flutter": "Flutter", "node": "Node",
        "yarn": "Yarn", "rust": "Rust", "golang": "Go", "dotnet": ".NET", "java": "Java",
        "eclipse": "Eclipse", "intellij": "IntelliJ", "pycharm": "PyCharm", "webstorm": "WebStorm",
        "datagrip": "DataGrip", "rider": "Rider", "clion": "CLion", "goland": "GoLand",
        "anaconda": "Anaconda", "miniconda": "Miniconda", "matlab": "MATLAB",
        "mathematica": "Mathematica", "rstudio": "RStudio", "stata": "Stata",
        "chrome": "Chrome", "chromium": "Chromium", "edge": "Edge", "brave": "Brave",
        "vivaldi": "Vivaldi", "opera": "Opera", "safari": "Safari", "arc": "Arc",
        "teams": "Teams", "outlook": "Outlook", "onedrive": "OneDrive", "sharepoint": "SharePoint",
        "onenote": "OneNote", "excel": "Excel", "word": "Word", "powerpoint": "PowerPoint",
        "discord": "Discord", "telegram": "Telegram", "signal": "Signal", "whatsapp": "WhatsApp",
        "mattermost": "Mattermost", "rocket": "Rocket", "jitsi": "Jitsi", "bluescape": "Bluescape",
        "box": "Box", "egnyte": "Egnyte", "syncthing": "Syncthing", "rclone": "rclone",
        "carbon": "Carbon", "copy": "Copy", "cloner": "Cloner", "superduper": "SuperDuper",
        "daisydisk": "DaisyDisk", "grandperspective": "GrandPerspective", "appcleaner": "AppCleaner",
        "keka": "Keka", "unarchiver": "Unarchiver", "betterzip": "BetterZip",
        "alfred": "Alfred", "raycast": "Raycast", "bartender": "Bartender", "rectangle": "Rectangle",
        "magnet": "Magnet", "istat": "iStat", "menus": "Menus", "stats": "Stats",
        "karabiner": "Karabiner", "elements": "Elements", "hammerspoon": "Hammerspoon",
        "iterm": "iTerm", "warp": "Warp", "kitty": "kitty", "alacritty": "Alacritty",
        "tunnelbear": "TunnelBear", "transmit": "Transmit", "forklift": "ForkLift",
        "sourcegraph": "Sourcegraph", "fork": "Fork", "tower": "Tower", "kaleidoscope": "Kaleidoscope",

        // Product nouns
        "cyber": "Cyber", "endpoint": "Endpoint", "workspace": "Workspace", "engine": "Engine",
        "framework": "Framework", "runtime": "Runtime", "toolkit": "Toolkit", "utility": "Utility",
        "utilities": "Utilities", "assistant": "Assistant", "helper": "Helper", "daemon": "Daemon",
        "service": "Service", "services": "Services", "sync": "Sync", "share": "Share",
        "meeting": "Meeting", "meetings": "Meetings", "conference": "Conference", "chat": "Chat",
        "mail": "Mail", "calendar": "Calendar", "notes": "Notes", "tasks": "Tasks",
        "board": "Board", "space": "Space", "hub": "Hub", "center": "Center", "centre": "Centre",
        "control": "Control", "access": "Access", "identity": "Identity", "vault": "Vault",
        "guard": "Guard", "shield": "Shield", "scan": "Scan",
        "analyzer": "Analyzer", "inspector": "Inspector", "profiler": "Profiler",
        "designer": "Designer", "builder": "Builder", "creator": "Creator", "maker": "Maker",
        "capture": "Capture", "record": "Record", "stream": "Stream", "broadcast": "Broadcast",
        "media": "Media", "audio": "Audio", "video": "Video", "photo": "Photo", "image": "Image",
        "graphics": "Graphics", "render": "Render", "print": "Print", "scanmate": "ScanMate",
        "file": "File", "files": "Files", "folder": "Folder", "disk": "Disk", "drives": "Drives",
        "network": "Network", "wifi": "Wi-Fi", "ethernet": "Ethernet", "proxy": "Proxy",
        "firewall": "Firewall", "malware": "Malware", "threat": "Threat", "detection": "Detection",
        "response": "Response", "compliance": "Compliance", "audit": "Audit", "report": "Report",
        "dashboard": "Dashboard", "analytics": "Analytics", "insights": "Insights",
        "admin": "Admin", "install": "Install", "setup": "Setup", "config": "Config",
        "settings": "Settings", "preferences": "Preferences", "extension": "Extension",
        "plugin": "Plugin", "addon": "Add-on", "module": "Module",
        "desk": "Desk", "support": "Support", "ticket": "Ticket",
        "virtual": "Virtual", "machine": "Machine", "container": "Container", "cluster": "Cluster",
        "database": "Database", "query": "Query", "table": "Table", "sheet": "Sheet",
        "mobile": "Mobile", "phone": "Phone", "tablet": "Tablet", "watch": "Watch",
        "smart": "Smart", "quick": "Quick", "fast": "Fast", "easy": "Easy", "simple": "Simple",
        "free": "Free", "lite": "Lite", "mini": "Mini", "micro": "Micro", "ultra": "Ultra",
        "plus": "Plus", "max": "Max", "one": "One", "go": "Go", "now": "Now", "live": "Live",
        "open": "Open", "edit": "Edit", "view": "View", "read": "Read", "write": "Write",
        "play": "Play", "send": "Send", "receive": "Receive", "transfer": "Transfer",
        "upload": "Upload", "download": "Download", "importer": "Importer", "exporter": "Exporter",
        "text": "Text", "code": "Code", "script": "Script", "shell": "Shell", "command": "Command",
        "line": "Line", "screen": "Screen", "window": "Window", "menu": "Menu", "bar": "Bar",
        "attributes": "Attributes", "properties": "Properties", "metadata": "Metadata",
        "rename": "Rename", "duplicate": "Duplicate", "compare": "Compare", "merge": "Merge",
        "search": "Search", "filter": "Filter", "sort": "Sort", "index": "Index",
        "better": "Better", "power": "Power", "super": "Super", "master": "Master",
        "total": "Total", "complete": "Complete", "full": "Full", "all": "All",
    ]

    /// Main entry point: returns a human-readable name for a label
    static func displayName(for label: String) -> String {
        // 1. Check known overrides first
        if let override = knownOverrides[label.lowercased()] {
            return override
        }

        // 2. Try splitting an all-lowercase run into known product words
        if let segmented = segmentedName(from: label) {
            return segmented
        }

        // 3. Apply heuristic: split on boundaries and capitalise
        return heuristicName(from: label)
    }

    /// Whether a display name still looks like a raw label — one long unbroken word — so the UI can
    /// invite the administrator to check it before it becomes a policy name.
    static func looksUnsegmented(_ displayName: String) -> Bool {
        displayName.split(separator: " ").contains(where: looksLikeOneRunOnWord)
    }

    /// Whether a single word is an unbroken run nobody can read.
    ///
    /// Per word, not per name. The old test asked whether the *whole* display name contained a
    /// space, so "Abetterfinderattributes 7" passed as fine — the trailing digit had given it a
    /// space, while the part that needed reading was untouched. A name is only as legible as its
    /// worst word.
    ///
    /// An internal capital counts as a boundary, because it is one a reader can see:
    /// "GrandPerspective" is legible and "Abetterfinderattributes" is not, at the same length.
    ///
    /// `nonisolated` because `looksUnsegmented` is called from wherever a name is rendered, and a
    /// pure string test has no business being main-actor bound (the project defaults every type to
    /// `MainActor`).
    nonisolated private static func looksLikeOneRunOnWord(_ word: Substring) -> Bool {
        guard word.count > 12, word.allSatisfy(\.isLetter) else { return false }
        return word.dropFirst().allSatisfy { !$0.isUppercase }
    }

    /// Splits an all-lowercase, all-letters label into `knownTokens`, longest match first.
    ///
    /// Returns `nil` unless **every** character is accounted for by **at least two** tokens. That
    /// all-or-nothing rule is what makes this safe: a partial match is far more likely to be a
    /// coincidence than a real word boundary, and a label that only half-decomposes falls through
    /// to the heuristic untouched.
    private static func segmentedName(from label: String) -> String? {
        // Capitals already give the heuristic boundaries to split on, so it can have those.
        //
        // **Digits used to disqualify a label here**, on the reasoning that a digit is a boundary
        // the heuristic can find on its own. It is — but finding *one* boundary is not the same as
        // segmenting: `abetterfinderattributes7` came out as "Abetterfinderattributes 7", which
        // splits off the 7 and leaves the part that actually needed reading untouched. The digit
        // was refusing the dictionary a look at the letters. Digit runs are now tokens of their
        // own, so that label segments into "A Better Finder Attributes 7".
        guard label == label.lowercased() else { return nil }

        var remaining = Substring(label)
        var parts: [String] = []
        while !remaining.isEmpty {
            if remaining.first?.isNumber == true {
                // A run of digits stands for itself — a version, an edition, "360".
                let digits = remaining.prefix { $0.isNumber }
                parts.append(String(digits))
                remaining = remaining.dropFirst(digits.count)
                continue
            }
            guard let token = longestToken(prefixing: remaining),
                  let display = knownTokens[token] else { return nil }
            parts.append(display)
            remaining = remaining.dropFirst(token.count)
        }
        return parts.count >= 2 ? parts.joined(separator: " ") : nil
    }

    /// The longest known token that starts `remaining`, so "mysql" wins over a shorter prefix.
    private static func longestToken(prefixing remaining: Substring) -> String? {
        var best: String?
        for token in knownTokens.keys where remaining.hasPrefix(token) {
            if best == nil || token.count > best!.count { best = token }
        }
        return best
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
