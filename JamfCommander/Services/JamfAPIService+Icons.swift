//
//  JamfAPIService+Icons.swift
//  JamfCommander
//
//  Self Service icon upload, preview download, and metadata via the Jamf Pro API.
//
//  Two-stage assignment (the modern, preferred path — not the legacy Classic
//  `fileuploads` endpoint):
//    1. Upload the image to the Jamf Pro icon library: `POST /api/v1/icon`
//       (multipart/form-data, part name `file`) → returns `{ id, url }`.
//    2. Attach the returned icon id to the policy by writing `<self_service_icon><id>…`
//       via `updatePolicySelfService` (Classic PUT). Attaching needs the Update Policies
//       privilege; the icon endpoints themselves require only a valid token (the OpenAPI
//       spec lists no dedicated privilege).
//
//  Previews use `GET /api/v1/icon/download/{id}` (tenant host, authenticated), which works
//  for the current icon, a freshly uploaded one, and a reused id alike.
//

import Foundation

extension JamfAPIService {

    /// Response shape for `POST /api/v1/icon` and `GET /api/v1/icon/{id}`.
    private struct JamfIconResponse: Codable {
        let id: Int
        let url: String
    }

    /// Uploads an image to the Jamf Pro icon library (`POST /api/v1/icon`,
    /// multipart/form-data, part name `file`) and returns the stored icon (id + url).
    /// This only adds the icon to the library; attaching it to a policy is a separate
    /// step (`updatePolicySelfService` with the icon id). Throws `APIError` on non-2xx.
    func uploadIcon(imageData: Data, filename: String, mimeType: String) async throws -> SelfServiceIcon {
        guard let token, !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: "\(baseURL)/api/v1/icon") else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let safeFilename = filename.isEmpty ? "icon.png" : filename
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(JamfIconResponse.self, from: data)
        return SelfServiceIcon(id: decoded.id, filename: safeFilename, uri: decoded.url)
    }

    /// Authenticated download of an icon's image bytes for preview. The bearer token is
    /// only attached when the URL is on the same host as the configured Jamf instance, so
    /// it is never sent to a third-party host (e.g. the icon CDN).
    func downloadIconData(from urlString: String) async throws -> Data {
        guard !baseURL.isEmpty else { throw APIError.authFailed }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token, let baseHost = URL(string: baseURL)?.host, url.host == baseHost {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }
        return data
    }

    /// Resolves an icon's CDN URL via `GET /api/v1/icon/{id}` (used for previews/caching).
    func fetchIconURL(id: Int) async throws -> String {
        let response = try await genericFetch(endpoint: "api/v1/icon/\(id)", responseType: JamfIconResponse.self)
        return response.url
    }

    /// Lightweight policy list (id + name only) for searching — one request, no detail
    /// hydration.
    func fetchPolicyList() async throws -> [PolicyListItem] {
        try await genericFetch(endpoint: "JSSResource/policies", responseType: PolicyListResponse.self).policies
    }

    /// Fetches the Self Service icon for each given policy id, returning only those that
    /// have one. Rate-limited (batches of 10 + 0.5s gaps + bounded retry) and degrades on
    /// per-item failure rather than aborting — see services-and-networking.md.
    func fetchSelfServiceIcons(forPolicyIDs ids: [Int]) async -> [PolicyIconHit] {
        var hits: [PolicyIconHit] = []
        let batchSize = 10
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: PolicyIconHit?.self) { group in
                for policyId in batch {
                    group.addTask {
                        for attempt in 1...3 {
                            do {
                                let editable = try await self.fetchPolicyEditable(id: policyId)
                                guard let icon = editable.selfService.icon, icon.id != nil else { return nil }
                                return PolicyIconHit(policyId: policyId, policyName: editable.name, icon: icon)
                            } catch {
                                if attempt == 3 { return nil }
                                try? await Task.sleep(nanoseconds: UInt64(0.5 * Double(1 << (attempt - 1)) * 1_000_000_000))
                            }
                        }
                        return nil
                    }
                }
                for await result in group {
                    if let result { hits.append(result) }
                }
            }
            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return hits
    }
}

/// One policy's Self Service icon, surfaced by the icon picker's search.
struct PolicyIconHit: Sendable {
    let policyId: Int
    let policyName: String
    let icon: SelfServiceIcon
}

private extension Data {
    /// Appends a UTF-8 string to the multipart body.
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
