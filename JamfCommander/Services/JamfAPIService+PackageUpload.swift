//
//  JamfAPIService+PackageUpload.swift
//  JamfCommander
//
//  Uploads a custom .pkg/.dmg to Jamf and creates the install policy for it — the same end result as
//  the Installomator flow, but with a file the administrator supplies instead of an upstream label.
//
//  Three requests, in this order, all confirmed against Jamf's API reference rather than inferred:
//
//  1. `POST api/v1/packages` (JSON) creates the package **record** and returns its id.
//     Required: packageName, fileName, categoryId, priority, fillUserTemplate, rebootRequired,
//     osInstall, suppressUpdates, suppressFromDock, suppressEula, suppressRegistration.
//     Privilege: Create Packages.
//  2. `POST api/v1/packages/{id}/upload` (multipart/form-data, part name `file`) uploads the file to
//     that record. 201 on success, 404 when the record is gone. Privileges: Read + Update Packages.
//  3. `POST JSSResource/policies/id/0` (Classic XML) creates the install policy, carrying
//     `<package_configuration>` where the Installomator flow carries `<scripts>`.
//
//  The upload is written to a temporary file and streamed from disk. A package is routinely a
//  gigabyte or more, so the in-memory multipart body used for Self Service icons
//  (`JamfAPIService+Icons`) is not an option here.
//
//  Nothing is ever rolled back automatically: if the upload or the policy fails after the record
//  exists, the caller reports exactly how far it got, so the cheap half can be retried without
//  pushing the file again.
//

import Foundation

extension JamfAPIService {

    // MARK: - Value types

    /// The metadata for a package record, as `POST api/v1/packages` expects it.
    ///
    /// The defaults are the conservative ones: a package that does not reboot, does not install an
    /// OS, and suppresses nothing. Anything that changes what happens on a Mac is the
    /// administrator's to switch on deliberately.
    struct JamfPackageDraft: Sendable {
        /// The display name in Jamf. Must be unique — `fetchPackageNames()` checks it before an
        /// upload starts, so a clash costs nothing rather than a wasted gigabyte.
        var packageName: String
        /// The name the file is stored under. Must match the file actually uploaded.
        var fileName: String
        /// Jamf category id, as a string — the API takes `categoryId` as a string, not a number.
        var categoryID: String
        var priority: Int = 10
        var info: String?
        var notes: String?
        var rebootRequired: Bool = false
        var osInstall: Bool = false
        var fillUserTemplate: Bool = false
        var suppressUpdates: Bool = false
        var suppressFromDock: Bool = false
        var suppressEula: Bool = false
        var suppressRegistration: Bool = false
    }

    /// Why an upload could not be completed, phrased so an administrator can act on it.
    ///
    /// Carries no response body — bodies can echo tenant data (root `CLAUDE.md`, invariant 4), so
    /// failures are classified from the status code alone.
    enum PackageUploadError: LocalizedError {
        case fileUnreadable(String)
        case temporaryFileUnavailable
        /// The upload endpoint is not present on this Jamf Pro.
        case uploadNotSupported
        case duplicatePackageName(String)
        case recordRejected
        case packageRecordMissingID
        case unauthorised
        case insufficientPrivileges
        case rateLimited
        case serverFailure(Int)
        case unexpectedResponse(Int)
        case networkFailure(String)

        var errorDescription: String? {
            switch self {
            case .fileUnreadable(let name):
                return "'\(name)' could not be read. Check the file still exists and that you have permission to open it."
            case .temporaryFileUnavailable:
                return "The upload could not be prepared on disk. Free up space at least the size of the package, then try again."
            case .uploadNotSupported:
                return "This Jamf Pro does not offer the package upload endpoint. Upload the file in Jamf Pro, then create the policy from the Policies module."
            case .duplicatePackageName(let name):
                return "A package called '\(name)' already exists in Jamf. Package names must be unique — change the display name and try again."
            case .recordRejected:
                return "Jamf rejected the package details. Check the display name, file name and category, then try again. Nothing was uploaded."
            case .packageRecordMissingID:
                return "Jamf created the package but did not return its id, so the file could not be uploaded to it. Check the package in Jamf before retrying."
            case .unauthorised:
                return "The Jamf session was refused (401). Reconnect to Jamf and try again."
            case .insufficientPrivileges:
                return "This API client is not permitted to manage packages (403). It needs the 'Create Packages', 'Read Packages' and 'Update Packages' privileges."
            case .rateLimited:
                return "Jamf is throttling requests (429). Wait a moment, then try again."
            case .serverFailure(let code):
                return "Jamf reported an internal error (HTTP \(code)). Check in Jamf whether the package arrived before retrying."
            case .unexpectedResponse(let code):
                return "Jamf rejected the request (HTTP \(code)). Check the package details in Jamf."
            case .networkFailure(let reason):
                return "Could not reach Jamf: \(reason)"
            }
        }
    }

    // MARK: - Reading

    /// Jamf Pro's own version, used to explain a missing upload endpoint rather than leaving a bare
    /// 404. Advisory: a failure here never blocks an upload.
    func fetchJamfProVersion() async throws -> String? {
        struct VersionResponse: Codable { let version: String? }
        return try await genericFetch(
            endpoint: "api/v1/jamf-pro-version",
            responseType: VersionResponse.self
        ).version
    }

    // MARK: - Step 1: the package record

    /// Creates the package record and returns its id. No file is sent here — this is the row in
    /// Jamf's package list that the upload then attaches the file to.
    func createPackageRecord(_ draft: JamfPackageDraft) async throws -> String {
        struct CreatePayload: Encodable {
            let packageName: String
            let fileName: String
            let categoryId: String
            let priority: Int
            let info: String?
            let notes: String?
            let fillUserTemplate: Bool
            let rebootRequired: Bool
            let osInstall: Bool
            let suppressUpdates: Bool
            let suppressFromDock: Bool
            let suppressEula: Bool
            let suppressRegistration: Bool
        }

        // Jamf returns `{ "id": "…", "href": "…" }`; the id has been seen as both a string and a
        // number across Pro API endpoints, so accept either rather than failing on a type.
        struct CreateResponse: Decodable {
            let id: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let stringID = try? container.decode(String.self, forKey: .id) {
                    id = stringID
                } else if let intID = try? container.decode(Int.self, forKey: .id) {
                    id = String(intID)
                } else {
                    id = nil
                }
            }

            enum CodingKeys: String, CodingKey { case id }
        }

        let payload = CreatePayload(
            packageName: draft.packageName,
            fileName: draft.fileName,
            categoryId: draft.categoryID,
            priority: draft.priority,
            info: draft.info,
            notes: draft.notes,
            fillUserTemplate: draft.fillUserTemplate,
            rebootRequired: draft.rebootRequired,
            osInstall: draft.osInstall,
            suppressUpdates: draft.suppressUpdates,
            suppressFromDock: draft.suppressFromDock,
            suppressEula: draft.suppressEula,
            suppressRegistration: draft.suppressRegistration
        )

        guard let token, !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/api/v1/packages") else {
            throw PackageUploadError.unauthorised
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw PackageUploadError.networkFailure(urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PackageUploadError.networkFailure("Jamf returned an unreadable response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Status only — the body is never read, logged or shown.
            print("[Packages] Package record rejected by Jamf (HTTP \(httpResponse.statusCode))")
            throw Self.recordFailure(status: httpResponse.statusCode, packageName: draft.packageName)
        }

        // A package record now exists that did not before. Signalled before the id is read back,
        // because the record exists in Jamf whether or not this app can parse its id. These Pro API
        // writes are sent directly rather than through `genericRequest`, so they do not inherit its
        // refresh signal and have to give it themselves.
        RefreshCoordinator.shared.requestRefresh()

        guard let id = (try? JSONDecoder().decode(CreateResponse.self, from: data))?.id, !id.isEmpty else {
            throw PackageUploadError.packageRecordMissingID
        }
        return id
    }

    /// Deletes a package record. Used only to clear up a record this app created moments earlier and
    /// could not upload to — never offered as a general way to remove packages.
    func deletePackageRecord(id: String) async throws {
        guard let token, !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/api/v1/packages/\(id)") else {
            throw PackageUploadError.unauthorised
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PackageUploadError.unexpectedResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // A record has gone. Narrow though this path is, a cache that kept it would list a package
        // that no longer exists.
        RefreshCoordinator.shared.requestRefresh()
    }

    // MARK: - Step 2: the file

    /// Uploads the file to an existing package record, streaming it from disk.
    ///
    /// The multipart envelope is assembled in the app's temporary directory and sent with
    /// `upload(for:fromFile:)`, so memory stays flat whatever the package weighs. That costs
    /// temporary disk roughly the size of the package, and the temporary file is removed on every
    /// path out — success, failure and cancellation alike.
    ///
    /// - Parameter onProgress: fraction sent, 0…1. Called on a URLSession queue, so the caller is
    ///   responsible for hopping to the main actor before touching UI state.
    func uploadPackageFile(
        packageID: String,
        fileURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let token, !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/api/v1/packages/\(packageID)/upload") else {
            throw PackageUploadError.unauthorised
        }

        // A file dropped onto the app arrives security-scoped; one chosen in an open panel does not.
        // Starting access is harmless in both cases, as long as it is only stopped when it started.
        let accessGranted = fileURL.startAccessingSecurityScopedResource()
        defer { if accessGranted { fileURL.stopAccessingSecurityScopedResource() } }

        let boundary = "JamfCommander-\(UUID().uuidString)"
        let bodyURL = try Self.writeMultipartEnvelope(around: fileURL, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let delegate = UploadProgressDelegate(onProgress: onProgress)

        let response: URLResponse
        do {
            (_, response) = try await Self.uploadSession.upload(for: request, fromFile: bodyURL, delegate: delegate)
        } catch let urlError as URLError {
            // A cancelled task is the administrator's own doing, not a failure to explain.
            if urlError.code == .cancelled { throw CancellationError() }
            throw PackageUploadError.networkFailure(urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PackageUploadError.networkFailure("Jamf returned an unreadable response.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            print("[Packages] Package upload rejected by Jamf (HTTP \(httpResponse.statusCode))")
            throw Self.uploadFailure(status: httpResponse.statusCode)
        }

        // The record's file — and with it the transfer status Jamf reports for it — has changed.
        RefreshCoordinator.shared.requestRefresh()
    }

    // MARK: - Step 3: the policy

    /// Creates a Self Service install policy for a package already in Jamf.
    ///
    /// Deliberately the sibling of `createInstallomatorPolicyAsync`: same general, scope and Self
    /// Service shape, and the same `PolicyCreationError` classification, with
    /// `<package_configuration>` in place of `<scripts>`. Policies are created enabled, as the
    /// Installomator flow creates them.
    ///
    /// - Returns: the new policy's id when Jamf returns one. The policy exists either way, so `nil`
    ///   means "created but the id could not be read" — never "not created".
    @discardableResult
    func createPackageInstallPolicy(
        policyName: String,
        packageID: String,
        packageName: String,
        categoryName: String,
        featureOnMainPage: Bool,
        displayInSelfServiceCategory: Bool,
        scopeConfig: DeploymentScopeConfig? = nil
    ) async throws -> Int? {
        let scope = scopeConfig ?? DeploymentScopeConfig()
        let featMain = featureOnMainPage ? "true" : "false"
        let dispInCat = displayInSelfServiceCategory ? "true" : "false"

        // Every dynamic value is escaped before it reaches the body (invariant 3) — a package called
        // "Acme Reader & Tools" is perfectly legal in Jamf and would otherwise break the request.
        let safePolicyName = Self.xmlEscape(policyName)
        let safeCategoryName = Self.xmlEscape(categoryName)
        let safePackageName = Self.xmlEscape(packageName)
        let safePackageID = Self.xmlEscape(packageID)

        let xmlBody = """
        <policy>
            <general>
                <name>\(safePolicyName)</name>
                <enabled>true</enabled>
                <frequency>Ongoing</frequency>
                <category>
                    <name>\(safeCategoryName)</name>
                </category>
            </general>
            \(scope.toScopeXML())
            <self_service>
                <use_for_self_service>true</use_for_self_service>
                <self_service_display_name>\(safePolicyName)</self_service_display_name>
                <install_button_text>Install</install_button_text>
                <force_users_to_view_description>false</force_users_to_view_description>
                <feature_on_main_page>\(featMain)</feature_on_main_page>
                <self_service_categories>
                    <category>
                        <name>\(safeCategoryName)</name>
                        <display_in>\(dispInCat)</display_in>
                        <feature_in>\(featMain)</feature_in>
                    </category>
                </self_service_categories>
            </self_service>
            <package_configuration>
                <packages>
                    <package>
                        <id>\(safePackageID)</id>
                        <name>\(safePackageName)</name>
                        <action>Install</action>
                    </package>
                </packages>
            </package_configuration>
        </policy>
        """

        guard let token, !baseURL.isEmpty,
              let url = URL(string: "\(baseURL)/JSSResource/policies/id/0") else {
            throw PolicyCreationError.unauthorised
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = xmlBody.data(using: .utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw PolicyCreationError.networkFailure(urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolicyCreationError.networkFailure("Jamf returned an unreadable response.")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            print("[Packages] Policy creation rejected by Jamf (HTTP \(httpResponse.statusCode))")
            throw Self.creationFailure(
                status: httpResponse.statusCode,
                body: data,
                policyName: policyName,
                categoryName: categoryName
            )
        }

        // A policy now exists that did not before — signalled before the id is parsed, for the same
        // reason as the package record above.
        RefreshCoordinator.shared.requestRefresh()

        return try? parseIDFromXMLResponse(data: data, elementName: "id")
    }

    // MARK: - Upload plumbing

    /// A session of its own for uploads. `URLSession.shared` is configured for API calls, and its
    /// resource timeout is not something to gamble a two-gigabyte push on: the request timeout here
    /// governs *inactivity*, while the resource timeout allows a genuinely slow link all day.
    nonisolated private static let uploadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        return URLSession(configuration: configuration)
    }()

    /// Reports how much of the body has gone. URLSession calls this on its own queue.
    private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let onProgress: @Sendable (Double) -> Void

        init(onProgress: @escaping @Sendable (Double) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            guard totalBytesExpectedToSend > 0 else { return }
            onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        }
    }

    /// Writes `--boundary … file bytes … --boundary--` to a temporary file and returns it.
    ///
    /// The file is copied through in chunks rather than read into a `Data`, because the whole point
    /// of this path is that the payload does not fit comfortably in memory.
    nonisolated private static func writeMultipartEnvelope(around fileURL: URL, boundary: String) throws -> URL {
        let fileManager = FileManager.default
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("jamfcommander-upload-\(UUID().uuidString)")

        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw PackageUploadError.temporaryFileUnavailable
        }

        let filename = sanitisedFileName(fileURL.lastPathComponent)
        let preamble = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: application/octet-stream\r\n\r\n"
        let epilogue = "\r\n--\(boundary)--\r\n"

        do {
            let output = try FileHandle(forWritingTo: temporaryURL)
            defer { try? output.close() }

            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }

            try output.write(contentsOf: Data(preamble.utf8))

            let chunkSize = 4 * 1024 * 1024
            while true {
                let chunk = try autoreleasepool { try input.read(upToCount: chunkSize) }
                guard let chunk, !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }

            try output.write(contentsOf: Data(epilogue.utf8))
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw PackageUploadError.fileUnreadable(fileURL.lastPathComponent)
        }

        return temporaryURL
    }

    /// A file name safe to sit inside a `Content-Disposition` header, and safe to store as the
    /// record's `fileName`. Quotes and line breaks are what turn a file name into header injection,
    /// so they are replaced rather than escaped; the caller uses this same name for the record, so
    /// the two can never disagree about what was uploaded.
    nonisolated static func sanitisedFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "package" : cleaned
    }

    // MARK: - Failure classification

    nonisolated private static func recordFailure(status: Int, packageName: String) -> PackageUploadError {
        switch status {
        case 400: return .recordRejected
        case 401: return .unauthorised
        case 403: return .insufficientPrivileges
        case 409: return .duplicatePackageName(packageName)
        case 429: return .rateLimited
        case 500...599: return .serverFailure(status)
        default: return .unexpectedResponse(status)
        }
    }

    nonisolated private static func uploadFailure(status: Int) -> PackageUploadError {
        switch status {
        // 404 here means the endpoint or the record is absent: on an older Jamf Pro it is the
        // endpoint, which is worth saying plainly rather than reporting a missing package.
        case 404, 405: return .uploadNotSupported
        case 401: return .unauthorised
        case 403: return .insufficientPrivileges
        case 429: return .rateLimited
        case 500...599: return .serverFailure(status)
        default: return .unexpectedResponse(status)
        }
    }
}
