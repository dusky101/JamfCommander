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

    /// Which policies install which package, keyed by package id.
    ///
    /// Jamf offers no reverse lookup, so this hydrates every policy and reads its
    /// `package_configuration`. That is the expensive scan `fetchInstallomatorPolicies` already
    /// performs, and it is paced the same way — batches of 10, 0.5s between batches, three attempts
    /// per policy with exponential backoff, and a policy that will not load is skipped rather than
    /// failing the whole scan. Call it once, lazily.
    func fetchPackagePolicyUsage() async throws -> [String: [String]] {
        let listResponse = try await genericFetch(
            endpoint: "JSSResource/policies",
            responseType: PolicyListResponse.self
        )

        var usage: [String: [String]] = [:]
        let batchSize = 10
        let batches = stride(from: 0, to: listResponse.policies.count, by: batchSize).map {
            Array(listResponse.policies[$0..<min($0 + batchSize, listResponse.policies.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: [(packageID: String, policyName: String)].self) { group in
                for item in batch {
                    group.addTask {
                        for attempt in 1...3 {
                            do {
                                let detail = try await self.fetchPolicyDetail(id: item.id)
                                let packages = detail.package_configuration?.packages ?? []
                                return packages.map {
                                    (packageID: String($0.id), policyName: detail.general.name)
                                }
                            } catch {
                                if attempt == 3 { return [] }
                                try? await Task.sleep(
                                    nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000)
                                )
                            }
                        }
                        return []
                    }
                }

                for await pairs in group {
                    for pair in pairs {
                        usage[pair.packageID, default: []].append(pair.policyName)
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

        print("[Packages] Package usage scan: \(usage.count) package(s) attached to a policy")
        return usage
    }
}
