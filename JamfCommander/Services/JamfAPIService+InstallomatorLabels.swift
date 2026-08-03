//
//  JamfAPIService+InstallomatorLabels.swift
//  JamfCommander
//
//  Reads a single Installomator label's own source from GitHub
//  (`fragments/labels/<label>.sh`) so the app can *explain* what the label will do on a Mac.
//
//  This is informational only, and deliberately so. Labels resolve their download URL by scraping
//  vendor pages in shell **on the target Mac at install time** — JamfCommander cannot and must not
//  try to replicate that. What it can do is read the label and answer the questions administrators
//  actually ask: does this handle Apple Silicon and Intel, and which version will it install?
//
//  Nothing here touches Jamf: it is an unauthenticated GET to raw.githubusercontent.com, so no
//  token is attached and a failure never blocks a deployment.
//

import Foundation

// MARK: - Parsed Label Source

/// What one Installomator label's source says about how it behaves.
struct InstallomatorLabelSource: Sendable, Hashable {
    let label: String

    /// The application name the label installs (`name="…"`).
    let appName: String?
    /// The archive type Installomator expects (`type="…"`), e.g. `dmg`, `pkg`, `zip`.
    let type: String?
    /// The Developer ID team the download is verified against (`expectedTeamID="…"`).
    let expectedTeamID: String?
    /// Processes Installomator will refuse to install over, or close first.
    let blockingProcesses: [String]

    /// The label chooses a different download per architecture, resolved on the Mac at install time.
    let isArchitectureAware: Bool
    /// The label works out the current version when it runs (a `curl`/scrape), rather than carrying one.
    let resolvesVersionAtRunTime: Bool
    /// A fixed version written into the label itself, if there is one.
    let pinnedVersion: String?

    /// Plain-English answer to "will this install the right binary on Apple Silicon and Intel?"
    var architectureSummary: String {
        isArchitectureAware
            ? "Chooses the Apple Silicon or Intel download on each Mac when it runs — no action needed."
            : "Uses one download for every Mac (typically a universal build or an Intel build that runs under Rosetta)."
    }

    /// Plain-English answer to "which version will land?"
    var versionSummary: String {
        if resolvesVersionAtRunTime {
            return "Looks up the current version when it runs, so each Mac gets whatever the vendor is shipping that day."
        }
        if let pinnedVersion {
            return "The label itself names version \(pinnedVersion)."
        }
        return "The label carries no version check — Installomator installs whatever the vendor's download URL currently serves."
    }

    /// Where this came from, for the panel's footer.
    var sourcePath: String { "fragments/labels/\(label).sh" }
}

// MARK: - Session Cache

/// Caches parsed label sources for the lifetime of the app run. An actor because the dashboard and
/// any open panel can ask for the same label concurrently.
actor InstallomatorLabelSourceCache {
    static let shared = InstallomatorLabelSourceCache()

    private var sources: [String: InstallomatorLabelSource] = [:]

    func cached(_ label: String) -> InstallomatorLabelSource? {
        sources[label.lowercased()]
    }

    func store(_ source: InstallomatorLabelSource) {
        sources[source.label.lowercased()] = source
    }
}

// MARK: - Fetch & Parse

extension JamfAPIService {

    /// Fetches and parses one label's source, using the session cache on repeat views.
    ///
    /// Throws on a network failure or a missing label so the caller can show a quiet, non-blocking
    /// message — never a blocked deployment.
    func fetchInstallomatorLabelSource(for label: String) async throws -> InstallomatorLabelSource {
        if let cached = await InstallomatorLabelSourceCache.shared.cached(label) {
            return cached
        }

        let urlString = "https://raw.githubusercontent.com/Installomator/Installomator/main/fragments/labels/\(label).sh"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        // No Authorization header: this is a public GitHub file, and the Jamf token must never be
        // sent to a third-party host.
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let script = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let source = Self.parseLabelSource(label: label, script: script)
        await InstallomatorLabelSourceCache.shared.store(source)
        return source
    }

    /// Parses the handful of fields the panel explains. Anything unrecognised simply stays nil —
    /// this reads a label to describe it, and must never fail loudly over an unexpected shape.
    static func parseLabelSource(label: String, script: String) -> InstallomatorLabelSource {
        // Installomator labels read `$(arch)` (or the `$arch` Installomator sets) to pick a download.
        // Either form means the choice is made on the Mac, not here.
        let isArchitectureAware = script.contains("$(arch)") || script.contains("$arch")

        // `appNewVersion=$(…)` or a backticked command means the version is resolved at run time;
        // a quoted literal means the label names a fixed version.
        let dynamicVersionMarkers = ["appNewVersion=$(", "appNewVersion=\"$(", "appNewVersion=`"]
        let resolvesVersionAtRunTime = dynamicVersionMarkers.contains { script.contains($0) }

        return InstallomatorLabelSource(
            label: label,
            appName: quotedValue(of: "name", in: script),
            type: quotedValue(of: "type", in: script),
            expectedTeamID: quotedValue(of: "expectedTeamID", in: script),
            blockingProcesses: blockingProcesses(in: script),
            isArchitectureAware: isArchitectureAware,
            resolvesVersionAtRunTime: resolvesVersionAtRunTime,
            pinnedVersion: resolvesVersionAtRunTime ? nil : quotedValue(of: "appNewVersion", in: script)
        )
    }

    /// First `key="value"` (or `key='value'`) assignment for `key`. Anchored so `name=` does not
    /// match `appName=` or `archiveName=`.
    private static func quotedValue(of key: String, in script: String) -> String? {
        let pattern = "(?:^|[^A-Za-z0-9_])\(key)\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script) else { return nil }
        let value = String(script[range]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Contents of `blockingProcesses=( … )`, quoted or bare.
    private static func blockingProcesses(in script: String) -> [String] {
        let pattern = "blockingProcesses\\s*=\\s*\\(([^)]*)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script) else { return [] }

        return String(script[range])
            .components(separatedBy: CharacterSet(charactersIn: " \t\n\""))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
