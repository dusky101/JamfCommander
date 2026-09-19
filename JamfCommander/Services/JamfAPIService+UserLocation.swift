//
//  JamfAPIService+UserLocation.swift
//  JamfCommander
//
//  Lookups for Buildings and Departments so we can resolve the IDs returned in
//  `userAndLocation` on a computer inventory record into human-readable names
//  for the list view, the inspector and the CSV export.
//

import Foundation

// MARK: - Lookup models

struct JamfLookupItem: Codable, Hashable {
    let id: String
    let name: String
}

struct JamfBuildingsResponse: Codable {
    let totalCount: Int?
    let results: [JamfLookupItem]
}

struct JamfDepartmentsResponse: Codable {
    let totalCount: Int?
    let results: [JamfLookupItem]
}

extension JamfAPIService {

    /// Fetch all buildings and return a dictionary keyed by id for fast lookup.
    func fetchBuildings(bypassingCache: Bool = false) async throws -> [String: String] {
        let endpoint = "api/v1/buildings?page-size=2000"
        if let cached = cachedValue(.buildings, as: [String: String].self, bypassingCache: bypassingCache) {
            return cached
        }
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfBuildingsResponse.self
        )
        let fresh = Dictionary(uniqueKeysWithValues: response.results.map { ($0.id, $0.name) })
        storeInCache(fresh, as: .buildings)
        return fresh
    }

    /// Fetch all departments and return a dictionary keyed by id for fast lookup.
    func fetchDepartments(bypassingCache: Bool = false) async throws -> [String: String] {
        let endpoint = "api/v1/departments?page-size=2000"
        if let cached = cachedValue(.departments, as: [String: String].self, bypassingCache: bypassingCache) {
            return cached
        }
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfDepartmentsResponse.self
        )
        let fresh = Dictionary(uniqueKeysWithValues: response.results.map { ($0.id, $0.name) })
        storeInCache(fresh, as: .departments)
        return fresh
    }
}
