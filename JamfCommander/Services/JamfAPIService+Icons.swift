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

    /// Tenant URL that serves an icon's image bytes at a given resolution
    /// (`GET /api/v1/icon/download/{id}`, `res` = `original` | `300` | `512`). For previews.
    func iconDownloadURLString(id: Int, resolution: String = "300") -> String {
        "\(baseURL)/api/v1/icon/download/\(id)?res=\(resolution)"
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
}

private extension Data {
    /// Appends a UTF-8 string to the multipart body.
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
