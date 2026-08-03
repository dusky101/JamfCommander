//
//  InstallomatorOverrides.swift
//  JamfCommander
//
//  Version pinning for an Installomator deployment, expressed as `key=value` argument overrides.
//
//  Why this works: `Installomator.sh` re-evaluates its `key=value` arguments *after* the label's
//  `case` block has run, so an argument passed as a script parameter overrides whatever the label
//  computed. Jamf exposes parameter4–parameter11; the create flow uses 4 (label), 5 (`DEBUG=0`) and
//  6 (`NOTIFY=silent`), leaving **parameter7–parameter11** free — five overrides per policy.
//
//  Why the values are the administrator's and never the app's: labels resolve their download URL by
//  scraping vendor pages in shell on the target Mac at install time. JamfCommander cannot know which
//  versions exist or where they live, and must not try — so it validates and substitutes what it is
//  given, and never invents a URL.
//

import Foundation

// MARK: - A single override

/// One `key=value` Installomator argument override typed by the administrator.
struct InstallomatorOverride: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }

    var isBlank: Bool {
        key.trimmingCharacters(in: .whitespaces).isEmpty && value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The exact string that will be written to a script parameter, with `{version}` substituted.
    func resolved(version: String?) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        let substituted = trimmedValue.replacingOccurrences(of: InstallomatorOverrides.versionPlaceholder,
                                                           with: version ?? "")
        return "\(trimmedKey)=\(substituted)"
    }
}

// MARK: - Validation & expansion

/// Validation and expansion rules for version pinning. Pure value logic, deliberately free of any
/// UI or networking so it can be exercised directly.
enum InstallomatorOverrides {

    /// Substituted with each pinned version, in override values and in the policy name.
    static let versionPlaceholder = "{version}"

    /// Jamf exposes parameter7–parameter11 to us, so five overrides per policy.
    static let maximumOverrides = 5

    /// Installomator label variables an administrator may override here.
    ///
    /// Restricted on purpose to the variables that describe *what to fetch and what version it is*.
    /// Deliberately excluded: `blockingProcesses` and `curlOptions` (shell array syntax, which does
    /// not survive a single `key=value` argument) and `updateTool`, `updateToolArguments` and
    /// `installerTool` (they name commands to execute, which is a far bigger gun than version pinning).
    static let allowedKeys: [String] = [
        "appNewVersion",
        "downloadURL",
        "archiveName",
        "packageID",
        "pkgName",
        "appName",
        "name",
        "type",
        "expectedTeamID",
        "versionKey",
        "targetDir",
    ]

    /// A problem that must be fixed before the run can proceed.
    enum Issue: Hashable {
        case unknownKey(String)
        case missingValue(String)
        case whitespaceInValue(String)
        case insecureDownloadURL
        case duplicateKey(String)
        case tooManyOverrides(Int)
        case malformedVersion(String)
        case versionPlaceholderWithoutVersions
        case versionsWithoutOverrides
        case nameMissingVersionPlaceholder

        var message: String {
            switch self {
            case .unknownKey(let key):
                return "'\(key)' is not an Installomator variable this app will set. Choose one from the list."
            case .missingValue(let key):
                return "'\(key)' has no value."
            case .whitespaceInValue(let key):
                return "The value for '\(key)' contains a space. Installomator reads each override as a single argument, so spaces are not supported."
            case .insecureDownloadURL:
                return "A pinned download URL must start with https://."
            case .duplicateKey(let key):
                return "'\(key)' is set more than once."
            case .tooManyOverrides(let count):
                return "\(count) overrides supplied, but a policy has room for only \(maximumOverrides)."
            case .malformedVersion(let version):
                return "'\(version)' is not a usable version — use digits, letters, dots, hyphens or underscores, with no spaces."
            case .versionPlaceholderWithoutVersions:
                return "An override uses \(versionPlaceholder) but no versions have been listed."
            case .versionsWithoutOverrides:
                return "Versions have been listed but no override tells Installomator what to fetch for each one — add at least a downloadURL or appNewVersion."
            case .nameMissingVersionPlaceholder:
                return "Add \(versionPlaceholder) to the policy name template, otherwise every pinned version would be created with the same name and Jamf would reject all but the first."
            }
        }
    }

    /// Resolves a policy name from the template. `{appName}` becomes the app's display name and
    /// `{version}` the pinned version; an unused `{version}` leaves no double space or trailing gap
    /// behind, so an unpinned run reads exactly as it did before pinning existed.
    static func policyName(template: String, appName: String, version: String?) -> String {
        var name = template.replacingOccurrences(of: "{appName}", with: appName)
        name = name.replacingOccurrences(of: versionPlaceholder, with: version ?? "")
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Splits a typed list of versions on commas, semicolons and newlines, trimming and
    /// de-duplicating while preserving the order they were typed in.
    static func parseVersions(_ text: String) -> [String] {
        var versions: [String] = []
        var seen = Set<String>()
        for piece in text.components(separatedBy: CharacterSet(charactersIn: ",;\n\r\t")) {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            versions.append(trimmed)
        }
        return versions
    }

    /// A version string is only allowed characters that are safe in both a policy name and a
    /// single shell argument.
    static func isUsableVersion(_ version: String) -> Bool {
        !version.isEmpty && version.allSatisfy { $0.isLetter || $0.isNumber || "._-+".contains($0) }
    }

    /// Everything wrong with the current pinning setup. Empty means it is safe to deploy.
    ///
    /// - Parameter nameTemplate: the policy name template, checked because pinning several versions
    ///   without `{version}` in the name would create identical names and be rejected by Jamf.
    static func issues(overrides: [InstallomatorOverride], versions: [String], nameTemplate: String) -> [Issue] {
        var issues: [Issue] = []
        let active = overrides.filter { !$0.isBlank }

        if active.count > maximumOverrides {
            issues.append(.tooManyOverrides(active.count))
        }

        var seenKeys = Set<String>()
        for override in active {
            let key = override.key.trimmingCharacters(in: .whitespaces)
            let value = override.value.trimmingCharacters(in: .whitespaces)

            if !allowedKeys.contains(key) {
                issues.append(.unknownKey(key.isEmpty ? "(no key)" : key))
                continue
            }
            if !seenKeys.insert(key).inserted {
                issues.append(.duplicateKey(key))
            }
            if value.isEmpty {
                issues.append(.missingValue(key))
                continue
            }
            if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                issues.append(.whitespaceInValue(key))
            }
            if key == "downloadURL", !value.lowercased().hasPrefix("https://") {
                issues.append(.insecureDownloadURL)
            }
        }

        for version in versions where !isUsableVersion(version) {
            issues.append(.malformedVersion(version))
        }

        let usesPlaceholder = active.contains { $0.value.contains(versionPlaceholder) }
        if usesPlaceholder && versions.isEmpty {
            issues.append(.versionPlaceholderWithoutVersions)
        }
        if !versions.isEmpty && active.isEmpty {
            issues.append(.versionsWithoutOverrides)
        }
        if versions.count > 1 && !nameTemplate.contains(versionPlaceholder) {
            issues.append(.nameMissingVersionPlaceholder)
        }

        // The same fault can be reported by several rows (five duplicate keys, say); say it once.
        var seenIssues = Set<Issue>()
        return issues.filter { seenIssues.insert($0).inserted }
    }

    /// Expands the setup into the policies to create: one per version, or a single unpinned policy
    /// when no versions are listed. Overrides beyond `maximumOverrides` are dropped here as a
    /// backstop — `issues(overrides:versions:)` blocks that case before it can be reached.
    static func variants(overrides: [InstallomatorOverride], versions: [String]) -> [InstallomatorPolicyVariant] {
        let active = Array(overrides.filter { !$0.isBlank }.prefix(maximumOverrides))

        guard !versions.isEmpty else {
            guard !active.isEmpty else { return [.unpinned] }
            return [InstallomatorPolicyVariant(version: nil, overrides: active.map { $0.resolved(version: nil) })]
        }

        return versions.map { version in
            InstallomatorPolicyVariant(
                version: version,
                overrides: active.map { $0.resolved(version: version) }
            )
        }
    }
}

// MARK: - One policy to create

/// One policy a run will create for a label: the version it pins, if any, plus the resolved
/// Installomator overrides written to parameter7–parameter11.
struct InstallomatorPolicyVariant: Sendable, Hashable {
    /// Substituted for `{version}` in the policy name. `nil` means the name carries no version.
    let version: String?
    /// Validated `key=value` strings, at most five.
    let overrides: [String]

    /// Today's behaviour: one policy, nothing pinned, no extra parameters written.
    static let unpinned = InstallomatorPolicyVariant(version: nil, overrides: [])
}
