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
    func fetchBuildings() async throws -> [String: String] {
        let endpoint = "api/v1/buildings?page-size=2000"
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfBuildingsResponse.self
        )
        return Dictionary(uniqueKeysWithValues: response.results.map { ($0.id, $0.name) })
    }

    /// Fetch all departments and return a dictionary keyed by id for fast lookup.
    func fetchDepartments() async throws -> [String: String] {
        let endpoint = "api/v1/departments?page-size=2000"
        let response = try await genericFetch(
            endpoint: endpoint,
            responseType: JamfDepartmentsResponse.self
        )
        return Dictionary(uniqueKeysWithValues: response.results.map { ($0.id, $0.name) })
    }
}
