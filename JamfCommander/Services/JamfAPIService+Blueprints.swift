//
//  JamfAPIService+Blueprints.swift
//  JamfCommander
//
//  Blueprint and platform device-group operations, served by the Platform API Gateway.
//
//  Unlike every other extension on `JamfAPIService`, these calls do not use `baseURL` or the
//  Jamf Pro bearer token. They go through `platform` (a `PlatformAPISession`) against
//  `https://{region}.api.jamfcloud.com`, with credentials from Settings. Being signed in to
//  Jamf Pro is therefore neither required nor sufficient for this module.
//
//  Endpoints confirmed against the Platform API reference:
//    GET    blueprints/v1/blueprints                     blueprints:read
//    POST   blueprints/v1/blueprints                     blueprints:create
//    GET    blueprints/v1/blueprints/{id}                blueprints:read
//    PATCH  blueprints/v1/blueprints/{id}                blueprints:update  (merge-patch+json)
//    DELETE blueprints/v1/blueprints/{id}                blueprints:delete
//    POST   blueprints/v1/blueprints/{id}/deploy         blueprints:deploy
//    POST   blueprints/v1/blueprints/{id}/undeploy       blueprints:deploy
//    GET    device-groups/v1/device-groups               device-groups:read
//

import Foundation

extension JamfAPIService {

    // MARK: - Constants

    private static let blueprintsPath = "blueprints/v1/blueprints"
    private static let deviceGroupsPath = "device-groups/v1/device-groups"

    /// The gateway's documented default page size.
    private static let platformPageSize = 100

    /// Ceiling on paging, so a misbehaving response can never spin forever. At 100 per page this
    /// covers 5,000 records, far beyond any realistic blueprint or device-group count.
    private static let platformMaxPages = 50

    /// Pause between pages. The gateway is rate-limited like the rest of the Jamf estate, so
    /// pages are fetched in sequence with a gap rather than fanned out.
    private static let platformPageDelay: UInt64 = 300_000_000 // 0.3s

    // MARK: - Configuration

    /// Whether Settings holds a complete set of Platform API credentials.
    ///
    /// Synchronous so a view can decide between the "not configured" state and a real fetch
    /// without an actor hop.
    var isPlatformConfigured: Bool {
        PlatformCredentialsStore.current() != nil
    }

    /// Applies the current Settings to the session and returns it ready to use.
    ///
    /// Called at the start of every operation so an edit in Settings takes effect immediately,
    /// and so a changed region or integration drops the token issued for the previous one.
    private func preparedPlatformSession() async throws -> PlatformAPISession {
        let credentials = PlatformCredentialsStore.current()
        await platform.configure(with: credentials)
        guard credentials != nil else { throw PlatformAPIError.notConfigured }
        return platform
    }

    /// Verifies the stored credentials by requesting a token and listing one blueprint.
    ///
    /// Used by the "Test Connection" button in Settings. Throws the real failure so the
    /// administrator can tell a wrong secret from a wrong region or a missing permission.
    func verifyPlatformConnection() async throws {
        let session = try await preparedPlatformSession()
        await session.invalidateToken()
        _ = try await session.sendDecoding(
            BlueprintListResponse.self,
            method: "GET",
            path: Self.blueprintsPath,
            query: [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "1")
            ]
        )
    }

    // MARK: - Blueprints

    /// Every blueprint in the environment.
    ///
    /// No `sort` parameter is sent: the reference does not state which fields the blueprints
    /// endpoint accepts for sorting, and an unrecognised one risks a rejected request, so the
    /// server's default order is used and the list is sorted by name here instead.
    func fetchBlueprints() async throws -> [Blueprint] {
        let session = try await preparedPlatformSession()

        var collected: [Blueprint] = []
        var page = 0

        while page < Self.platformMaxPages {
            let response = try await session.sendDecoding(
                BlueprintListResponse.self,
                method: "GET",
                path: Self.blueprintsPath,
                query: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(Self.platformPageSize))
                ]
            )

            collected.append(contentsOf: response.results)

            // A short page is the last page.
            if response.results.count < Self.platformPageSize { break }
            if let total = response.totalCount, collected.count >= total { break }

            page += 1
            try await Task.sleep(nanoseconds: Self.platformPageDelay)
        }

        return collected.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// One blueprint's full definition, pretty-printed for the inspector and the edit sheet.
    ///
    /// Returned as text rather than a decoded model so an unfamiliar component payload survives
    /// a view-then-edit round trip untouched.
    func fetchBlueprintJSON(id: String) async throws -> String {
        let session = try await preparedPlatformSession()
        let data = try await session.send(
            method: "GET",
            path: "\(Self.blueprintsPath)/\(id)"
        )
        return BlueprintPayload.prettyPrinted(data)
    }

    /// Creates a blueprint. `body` comes from `BlueprintPayload.makeCreateBody(json:scope:)`.
    func createBlueprint(body: Data) async throws {
        let session = try await preparedPlatformSession()
        try await session.send(
            method: "POST",
            path: Self.blueprintsPath,
            body: body
        )
    }

    /// Updates a blueprint. `body` comes from `BlueprintPayload.makeUpdateBody(json:scope:)`.
    ///
    /// The content type is `application/merge-patch+json`, which this endpoint requires — sending
    /// plain `application/json` is answered with a 415.
    func updateBlueprint(id: String, body: Data) async throws {
        let session = try await preparedPlatformSession()
        try await session.send(
            method: "PATCH",
            path: "\(Self.blueprintsPath)/\(id)",
            body: body,
            contentType: "application/merge-patch+json"
        )
    }

    /// Deletes a blueprint. Irreversible, and it affects every device the blueprint is scoped to.
    func deleteBlueprint(id: String) async throws {
        let session = try await preparedPlatformSession()
        try await session.send(
            method: "DELETE",
            path: "\(Self.blueprintsPath)/\(id)"
        )
    }

    /// Starts deployment. The server answers 202 — the work continues after the call returns, so
    /// the list's deployment state is what confirms the outcome, not this method returning.
    func deployBlueprint(id: String) async throws {
        let session = try await preparedPlatformSession()
        try await session.send(
            method: "POST",
            path: "\(Self.blueprintsPath)/\(id)/deploy"
        )
    }

    /// Starts undeployment, which withdraws the blueprint's declarations from its scoped devices.
    func undeployBlueprint(id: String) async throws {
        let session = try await preparedPlatformSession()
        try await session.send(
            method: "POST",
            path: "\(Self.blueprintsPath)/\(id)/undeploy"
        )
    }

    // MARK: - Device groups

    /// Platform device groups, used to scope a blueprint.
    ///
    /// These carry UUIDs and are a different set from `fetchComputerGroups()`, which returns
    /// numeric Jamf Pro computer groups. A Jamf Pro group ID is not accepted in
    /// `scope.deviceGroups`.
    func fetchPlatformDeviceGroups() async throws -> [PlatformDeviceGroup] {
        let session = try await preparedPlatformSession()

        var collected: [PlatformDeviceGroup] = []
        var page = 0

        while page < Self.platformMaxPages {
            let response = try await session.sendDecoding(
                PlatformDeviceGroupPage.self,
                method: "GET",
                path: Self.deviceGroupsPath,
                query: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(Self.platformPageSize))
                ]
            )

            collected.append(contentsOf: response.results)

            if response.hasNext != true { break }
            if response.results.isEmpty { break }

            page += 1
            try await Task.sleep(nanoseconds: Self.platformPageDelay)
        }

        return collected.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Blueprint components

extension JamfAPIService {

    /// Note the path segment is `blueprint-components`, not `components`.
    private static let componentsPath = "blueprints/v1/blueprint-components"

    /// The component catalogue for this environment.
    ///
    /// This is what a blueprint's `steps[].components[].identifier` must be one of, and it is
    /// tenant- and version-dependent rather than fixed — which is why the app reads it rather than
    /// hard-coding the list published in the API reference.
    func fetchBlueprintComponents() async throws -> [BlueprintComponent] {
        let session = try await preparedPlatformSession()

        var collected: [BlueprintComponent] = []
        var page = 0

        while page < Self.platformMaxPages {
            let response = try await session.sendDecoding(
                BlueprintComponentListResponse.self,
                method: "GET",
                path: Self.componentsPath,
                query: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: String(Self.platformPageSize))
                ]
            )

            collected.append(contentsOf: response.results)

            if response.results.count < Self.platformPageSize { break }
            if let total = response.totalCount, collected.count >= total { break }

            page += 1
            try await Task.sleep(nanoseconds: Self.platformPageDelay)
        }

        return collected.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
    }

    /// The whole component-list response as text, so anything the decoder did not model is still
    /// visible rather than silently dropped.
    func fetchBlueprintComponentsRawJSON() async throws -> String {
        let session = try await preparedPlatformSession()
        let data = try await session.send(
            method: "GET",
            path: Self.componentsPath,
            query: [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: String(Self.platformPageSize))
            ]
        )
        return BlueprintPayload.prettyPrinted(data)
    }

    /// One component's full definition, including whatever schema it publishes for its
    /// `configuration` object.
    func fetchBlueprintComponentJSON(identifier: String) async throws -> String {
        let session = try await preparedPlatformSession()
        let data = try await session.send(
            method: "GET",
            path: "\(Self.componentsPath)/\(identifier)"
        )
        return BlueprintPayload.prettyPrinted(data)
    }
}
