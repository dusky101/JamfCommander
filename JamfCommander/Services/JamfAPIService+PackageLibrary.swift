//
//  JamfAPIService+PackageLibrary.swift
//  JamfCommander
//
//  Reads the packages already in Jamf, and works out which of them a policy actually installs.
//
//  Separate from `+PackageUpload` on purpose: that file is about getting one new package *in*, this
//  one is about seeing what is already there. Everything here is read-only.
//
//  Two requests of very different weight:
//
//  · `GET api/v1/packages` is one cheap call that returns the whole library.
//  · Working out which packages are attached to a policy is not cheap. Jamf offers no "which policies
//    use package X" endpoint, so every policy has to be hydrated and its `package_configuration`
//    read — the same throttled scan `fetchInstallomatorPolicies` performs, paced identically.
//    Callers should run it once, lazily, and never on a keystroke.
//

import Foundation

// MARK: - A package already in Jamf

/// One row of Jamf's package library.
///
/// Every field but the id is optional and decoded defensively: this list is rendered in a view, and a
/// single package with an unexpected shape must never blank the whole library (see
/// `models-and-decoding.md`). Only fields Jamf documents for this endpoint are modelled — nothing is
/// invented, which is why a package's size is absent: the endpoint does not return one.
struct JamfPackage: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let packageName: String
    let fileName: String
    let categoryID: String?
    let info: String?
    let notes: String?
    let manifestFileName: String?
    /// Jamf's own view of whether the file reached its distribution point. The values vary between
    /// Jamf Pro versions, so it is shown as given rather than interpreted.
    let cloudTransferStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, packageName, fileName
        // Spelled out so the property keeps the project's `ID` casing while still matching Jamf's
        // key — without it, the synthesised encoder has no case to map `categoryID` onto.
        case categoryID = "categoryId"
        case info, notes, manifestFileName, cloudTransferStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Pro API ids have been seen as both string and number; accept either.
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = ""
        }

        packageName = (try? container.decode(String.self, forKey: .packageName)) ?? ""
        fileName = (try? container.decode(String.self, forKey: .fileName)) ?? ""

        if let stringCategory = try? container.decode(String.self, forKey: .categoryID) {
            categoryID = stringCategory
        } else if let intCategory = try? container.decode(Int.self, forKey: .categoryID) {
            categoryID = String(intCategory)
        } else {
            categoryID = nil
        }

        info = try? container.decode(String.self, forKey: .info)
        notes = try? container.decode(String.self, forKey: .notes)
        manifestFileName = try? container.decode(String.self, forKey: .manifestFileName)
        cloudTransferStatus = try? container.decode(String.self, forKey: .cloudTransferStatus)
    }

    /// Display name first, falling back to the file name — a package with neither is not worth a row.
    var displayName: String {
        if !packageName.isEmpty { return packageName }
        return fileName.isEmpty ? "Package \(id)" : fileName
    }
}

// MARK: - Reads

extension JamfAPIService {

    /// Every package in the tenant's library, sorted by display name.
    ///
    /// One request. `page-size=2000` matches the ceiling the rest of the app uses for Pro API lists;
    /// a library larger than that would need paging, which no tenant this app targets has needed.
    func fetchJamfPackages() async throws -> [JamfPackage] {
        struct PackageListResponse: Codable {
            let results: [JamfPackage]?
        }

        let response = try await genericFetch(
            endpoint: "api/v1/packages?page-size=2000&sort=packageName:asc",
            responseType: PackageListResponse.self
        )
        return (response.results ?? [])
            .filter { !$0.id.isEmpty }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Every package display name in the tenant, for the pre-flight uniqueness check before an upload.
    /// Reads the same list as `fetchJamfPackages()` so there is one decoder, not two.
    func fetchPackageNames() async throws -> [String] {
        try await fetchJamfPackages().map(\.packageName).filter { !$0.isEmpty }
    }

    /// Reads every policy **once** and answers everything the policy record can tell us: the policy
    /// itself (category, enabled state, scope), which packages it installs, and whether it is an
    /// Installomator deployment.
    ///
    /// Jamf offers no reverse lookup for any of it, so each answer used to cost a full scan of its
    /// own — `fetchPolicies`, the old `fetchPackagePolicyUsage` and `fetchInstallomatorPolicies` all
    /// hydrate the same policies for different fields. Anything needing more than one (the packages
    /// export, the Redundant audit) paid for the tenant's policies twice over. Pacing is unchanged:
    /// batches of 10, 0.5s between batches, three attempts per policy with exponential backoff, and
    /// a policy that will not load is skipped rather than failing the whole scan.
    ///
    /// - Parameter knownScriptIDs: Additional script ids to treat as Installomator, so a renamed
    ///   script is still detected (see `fetchInstallomatorScriptIDs()`).
    func scanPolicyEstate(knownScriptIDs: Set<String> = []) async throws -> PolicyEstateScan {
        let listResponse = try await genericFetch(
            endpoint: "JSSResource/policies",
            responseType: PolicyListResponse.self
        )

        var usage: [String: [String]] = [:]
        var installomator: [InstallomatorPolicyInfo] = []
        var policies: [Policy] = []

        let batchSize = 10
        let batches = stride(from: 0, to: listResponse.policies.count, by: batchSize).map {
            Array(listResponse.policies[$0..<min($0 + batchSize, listResponse.policies.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: PolicyPackageFindings.self) { group in
                for item in batch {
                    group.addTask {
                        for attempt in 1...3 {
                            do {
                                let detail = try await self.fetchPolicyDetail(id: item.id)
                                let packages = detail.package_configuration?.packages ?? []
                                return PolicyPackageFindings(
                                    packagePairs: packages.map {
                                        PackagePolicyPair(
                                            packageID: String($0.id),
                                            policyName: detail.general.name
                                        )
                                    },
                                    installomator: Self.installomatorInfo(
                                        in: detail,
                                        knownScriptIDs: knownScriptIDs
                                    ),
                                    policy: Policy(
                                        id: detail.general.id,
                                        name: detail.general.name,
                                        categoryId: detail.general.category?.id,
                                        categoryName: detail.general.category?.name,
                                        enabled: detail.general.enabled,
                                        scope: detail.scope,
                                        scopeTargetsAnything: detail.scopeTargets.targetsAnything
                                    )
                                )
                            } catch {
                                if attempt == 3 { return .none }
                                try? await Task.sleep(
                                    nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000)
                                )
                            }
                        }
                        return .none
                    }
                }

                for await findings in group {
                    for pair in findings.packagePairs {
                        usage[pair.packageID, default: []].append(pair.policyName)
                    }
                    if let info = findings.installomator {
                        installomator.append(info)
                    }
                    if let policy = findings.policy {
                        policies.append(policy)
                    }
                }
            }

            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        // Stable order, so a row's policy list doesn't reshuffle between scans.
        for (packageID, policyNames) in usage {
            usage[packageID] = policyNames.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        installomator.sort {
            $0.policyName.localizedCaseInsensitiveCompare($1.policyName) == .orderedAscending
        }
        policies.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        print("[Packages] Estate scan: \(policies.count) policy/policies read, \(usage.count) package(s) attached to a policy, \(installomator.count) Installomator policy/policies")
        return PolicyEstateScan(policies: policies, packageUsage: usage, installomator: installomator)
    }
}

// MARK: - Scan results

/// What one pass over every policy reveals.
///
/// The three parts are deliberately different in kind. `policies` is the policies themselves;
/// `packageUsage` is about packages in Jamf's library; `installomator` is about policies that
/// install software **without** a library package, by running the Installomator script against a
/// label. A tenant's software estate is the union of the last two.
struct PolicyEstateScan: Sendable {
    /// Every policy that could be read, hydrated with category, enabled state and scope, sorted by
    /// name. A policy Jamf would not return after three attempts is absent rather than guessed at.
    let policies: [Policy]
    /// Names of the policies that install each package, keyed by package id. A package id absent
    /// from this map is installed by nothing.
    let packageUsage: [String: [String]]
    /// Policies that install software through Installomator, sorted by policy name.
    let installomator: [JamfAPIService.InstallomatorPolicyInfo]
}

/// One policy's contribution to a scan, gathered inside the task group before it is merged.
private struct PolicyPackageFindings: Sendable {
    let packagePairs: [PackagePolicyPair]
    let installomator: JamfAPIService.InstallomatorPolicyInfo?
    /// `nil` when the policy could not be read — it is then left out of the scan entirely rather
    /// than appearing as an empty record that would read as "no category, disabled, unscoped".
    let policy: Policy?

    /// A policy that could not be read.
    ///
    /// `nonisolated` because the scan reads it from inside a `TaskGroup`: this project defaults to
    /// main-actor isolation, which would otherwise make a plain `static let` main-actor-bound (a
    /// warning today, an error in the Swift 6 language mode).
    nonisolated static let none = PolicyPackageFindings(packagePairs: [], installomator: nil, policy: nil)
}

private struct PackagePolicyPair: Sendable {
    let packageID: String
    let policyName: String
}
