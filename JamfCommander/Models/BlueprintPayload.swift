//
//  BlueprintPayload.swift
//  JamfCommander
//
//  Turns administrator-supplied JSON into a Platform API request body.
//
//  The pasted JSON is passed through as-is apart from two deliberate changes: the scope is
//  replaced when one is chosen in the picker, and server-managed fields are removed. Nothing
//  else is rewritten, because the `configuration` object of a component can carry any Apple
//  payload key — round-tripping it through a strict Swift model would silently drop whatever
//  this app does not know about.
//

import Foundation

// MARK: - Declarations

/// Which DDM status channel a declaration applies on.
///
/// Values are the wire form seen in a real deployed blueprint from the tenant, not inferred.
nonisolated enum DeclarationChannel: String, CaseIterable, Identifiable, Sendable {
    case system = "SYSTEM"
    case user = "USER"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .user: return "User"
        }
    }

    var explanation: String {
        switch self {
        case .system: return "Applies to the device, whoever is logged in."
        case .user: return "Applies to specific user accounts."
        }
    }
}

// MARK: - Scope selection

/// What the create/edit sheet should do with `scope.deviceGroups`.
nonisolated enum BlueprintScopeSelection: Equatable, Sendable {
    /// Leave whatever the supplied JSON already contains.
    case keepExisting
    /// Replace the scope with these platform device group UUIDs.
    case groups([String])
    /// Send an empty `deviceGroups` array.
    ///
    /// Jamf documents `scope.deviceGroups` as required with at least one entry, so the server
    /// may refuse this. The option exists because only a live call settles it, and the real
    /// response is reported either way.
    case unscoped
}

// MARK: - Errors

nonisolated enum BlueprintPayloadError: LocalizedError, Sendable {
    case empty
    case notJSON(String)
    case notAnObject
    case missingName
    case nameTooLong(Int)
    case missingScope
    case scopeNotAnObject
    case deviceGroupsNotStrings
    case looksLikeAppleDeclaration(String?)
    case missingSteps
    case stepsNotAnArray
    case tooManySteps(Int)
    case stepNotAnObject(Int)
    case componentsMissing(Int)
    case componentsEmpty(Int)
    case tooManyComponents(Int, Int)
    case serialisationFailed
    case noDeclarationsFound
    case declarationTypeRequired
    case declarationTypeNotApple(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "No JSON supplied. Paste a blueprint definition or choose a file."
        case .notJSON(let detail):
            return "That is not valid JSON: \(detail)"
        case .notAnObject:
            return "The JSON must be a single object starting with { and ending with }."
        case .missingName:
            return "The blueprint needs a \"name\". Jamf requires it and it cannot be empty."
        case .nameTooLong(let count):
            return "The blueprint name is \(count) characters. Jamf allows up to 200."
        case .missingScope:
            return "The JSON has no \"scope\". Choose device groups below, or add a scope object to the JSON."
        case .scopeNotAnObject:
            return "\"scope\" must be an object containing a \"deviceGroups\" array."
        case .deviceGroupsNotStrings:
            return "\"scope.deviceGroups\" must be an array of device group UUID strings."
        case .looksLikeAppleDeclaration(let type):
            let named = type.map { " (\($0))" } ?? ""
            return "That looks like an Apple declaration\(named), not a blueprint. Use \"Wrap as Blueprint\" in the Definition panel to convert it."
        case .missingSteps:
            return "The JSON has no \"steps\". Jamf requires the key, though an empty array is accepted."
        case .stepsNotAnArray:
            return "\"steps\" must be an array."
        case .tooManySteps(let count):
            return "The blueprint has \(count) steps. Jamf allows at most 10."
        case .stepNotAnObject(let index):
            return "Step \(index + 1) is not an object."
        case .componentsMissing(let index):
            return "Step \(index + 1) has no \"components\" array. Jamf requires one."
        case .componentsEmpty(let index):
            return "Step \(index + 1) has an empty \"components\" array. Jamf requires at least one component per step."
        case .tooManyComponents(let index, let count):
            return "Step \(index + 1) has \(count) components. Jamf allows at most 100."
        case .serialisationFailed:
            return "The blueprint could not be prepared for sending."
        case .declarationTypeRequired:
            return "Enter the declaration type this payload belongs to, for example com.apple.configuration.extensible-sso. The payload itself does not say which one it is."
        case .declarationTypeNotApple(let type):
            return "“\(type)” is not an Apple declaration type. These begin com.apple.configuration. for settings, or com.apple.asset. for supporting data."
        case .noDeclarationsFound:
            return "No Apple declarations were found in that JSON. A declaration needs a \"Type\" starting with com.apple. and a \"Payload\"."
        }
    }
}

// MARK: - Payload building

nonisolated enum BlueprintPayload {

    /// Fields the server owns. Sending them back is either rejected or meaningless, so they are
    /// removed — which is what makes "copy a blueprint's JSON from the inspector and paste it
    /// into the create sheet" work as a clone.
    ///
    /// `divisionId` is included because Jamf rejects a PATCH carrying it with a 400 and
    /// `DIVISION_ASSIGNMENT_NOT_ALLOWED`, whether it holds a value or null.
    static let serverManagedKeys = ["id", "created", "updated", "deploymentState", "divisionId"]

    /// The component that carries raw Apple declarations.
    ///
    /// Taken from a real deployed blueprint in the tenant — it is **not** in the identifier enum
    /// published in the API reference, so it could not have been derived from the documentation.
    /// Exposed here rather than buried, because the catalogue is tenant- and version-dependent:
    /// if a future environment uses a different identifier, this is the one line to change, and the
    /// wrapped JSON shows it plainly in the editor so it can be corrected by hand.
    static let declarationComponentIdentifier = "com.jamf.ddm-strict"

    /// Default step name, matching what Jamf's own blueprint builder writes.
    static let defaultStepName = "Components in this blueprint"

    static let maxNameLength = 200
    static let maxSteps = 10
    static let maxComponentsPerStep = 100

    // MARK: Create

    /// Builds the body for `POST /blueprints/v1/blueprints`.
    ///
    /// Every field Jamf documents as required is checked here so an obvious mistake is caught
    /// before it reaches production, rather than after a round trip.
    static func makeCreateBody(
        json: String,
        scope: BlueprintScopeSelection,
        name: String? = nil,
        description: String? = nil
    ) throws -> Data {
        var object = try parseObject(json)
        try rejectAppleDeclaration(object)
        stripServerManagedKeys(&object)
        applyIdentity(name: name, description: description, to: &object)
        applyScope(scope, to: &object)

        try validateName(in: object, required: true)
        try validateScope(in: object, required: true)
        try validateSteps(in: object, required: true)

        return try serialise(object)
    }

    // MARK: Update

    /// Builds the body for `PATCH /blueprints/v1/blueprints/{id}`.
    ///
    /// The endpoint takes `application/merge-patch+json`, so anything the JSON leaves out is
    /// left untouched on the server. Only the keys actually present are validated.
    static func makeUpdateBody(
        json: String,
        scope: BlueprintScopeSelection,
        name: String? = nil,
        description: String? = nil
    ) throws -> Data {
        var object = try parseObject(json)
        try rejectAppleDeclaration(object)
        stripServerManagedKeys(&object)
        applyIdentity(name: name, description: description, to: &object)
        applyScope(scope, to: &object)

        try validateName(in: object, required: false)
        try validateScope(in: object, required: false)
        try validateSteps(in: object, required: false)

        return try serialise(object)
    }

    // MARK: Declarations

    /// The Apple declaration types in a document, if it holds any.
    ///
    /// Returns empty for anything that is already a blueprint (it has `steps`), so a normal
    /// definition is never mistaken for DDM output. A declaration is recognised by having both a
    /// `Type` beginning `com.apple.` and a payload — both are required, so an arbitrary object
    /// carrying one or the other does not match.
    static func declarationTypes(in json: String) -> [String] {
        guard let parsed = parseLoosely(json) else { return [] }

        if let object = parsed as? [String: Any] {
            guard object["steps"] == nil else { return [] }

            if let type = declarationType(of: object) { return [type] }

            // Already in the wrapped form: { "declarations": [ ... ] }
            if let nested = object["declarations"] as? [[String: Any]] {
                return nested.compactMap(declarationType(of:))
            }
            return []
        }

        if let array = parsed as? [[String: Any]] {
            return array.compactMap(declarationType(of:))
        }

        return []
    }

    /// True when the document is already a blueprint, so it needs no wrapping.
    static func looksLikeBlueprint(_ json: String) -> Bool {
        guard let object = parseLoosely(json) as? [String: Any] else { return false }
        return object["steps"] != nil
    }

    /// Wraps Apple declarations — or a bare payload — into a complete blueprint document.
    ///
    /// Two shapes come out of the Jamf DDM app and both are handled:
    ///
    /// - A **full declaration**, carrying `Type` (`com.apple.…`) and `Payload`. `Identifier` and
    ///   `ServerToken` are dropped, because Jamf generates both and a real deployed blueprint
    ///   carries neither inside its declarations.
    /// - A **bare payload**, which is only the settings. Nothing in it identifies which declaration
    ///   it belongs to — note that extensible-sso's payload has its own `Type` key holding
    ///   "Redirect" — so `declarationType` must be supplied by the caller.
    static func wrapDeclarations(
        json: String,
        channel: DeclarationChannel,
        declarationType suppliedType: String? = nil,
        name: String? = nil,
        stepName: String = defaultStepName
    ) throws -> String {
        guard let parsed = parseLoosely(json) else { throw BlueprintPayloadError.noDeclarationsFound }

        var sources: [[String: Any]] = []
        if let object = parsed as? [String: Any] {
            if let nested = object["declarations"] as? [[String: Any]] {
                sources = nested
            } else {
                sources = [object]
            }
        } else if let array = parsed as? [[String: Any]] {
            sources = array
        }

        var declarations = sources.compactMap { source -> [String: Any]? in
            guard let type = declarationType(of: source) else { return nil }
            let payload = (source["Payload"] as? [String: Any])
                ?? (source["payload"] as? [String: Any])
                ?? [:]

            return [
                // Apple's own split: com.apple.asset.* are assets, com.apple.configuration.* are
                // configurations. Documented in Jamf's Blueprints guide with one example of each.
                "kind": type.hasPrefix("com.apple.asset.") ? "ASSET" : "CONFIGURATION",
                "channelType": channel.rawValue,
                "type": type,
                "payload": payload
            ]
        }

        // Nothing recognisable as a declaration: treat the whole document as one payload, which is
        // what the DDM app exports when it gives you settings rather than a wrapped declaration.
        if declarations.isEmpty, let payload = parsed as? [String: Any] {
            let trimmedType = (suppliedType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedType.isEmpty else {
                throw BlueprintPayloadError.declarationTypeRequired
            }
            guard trimmedType.hasPrefix("com.apple.") else {
                throw BlueprintPayloadError.declarationTypeNotApple(trimmedType)
            }

            declarations = [[
                "kind": trimmedType.hasPrefix("com.apple.asset.") ? "ASSET" : "CONFIGURATION",
                "channelType": channel.rawValue,
                "type": trimmedType,
                "payload": payload
            ]]
        }

        guard !declarations.isEmpty else { throw BlueprintPayloadError.noDeclarationsFound }

        var blueprint: [String: Any] = [
            // A placeholder the scope picker replaces on save; present so the document is a
            // structurally complete blueprint the moment it is wrapped.
            "scope": ["deviceGroups": [String]()],
            "steps": [
                [
                    "name": stepName,
                    "activationPredicate": NSNull(),
                    "components": [
                        [
                            "identifier": declarationComponentIdentifier,
                            "configuration": ["declarations": declarations]
                        ]
                    ]
                ]
            ]
        ]

        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            blueprint["name"] = name
        }

        let data = try serialise(blueprint)
        return prettyPrinted(data)
    }

    private static func parseLoosely(_ json: String) -> Any? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// The declaration type of an object, or nil when it is not a declaration.
    private static func declarationType(of object: [String: Any]) -> String? {
        guard let type = (object["Type"] as? String) ?? (object["type"] as? String),
              type.hasPrefix("com.apple.") else { return nil }
        guard object["Payload"] != nil || object["payload"] != nil else { return nil }
        return type
    }

    // MARK: Inspection helpers

    /// Pretty-prints a JSON body for the inspector and the editor.
    static func prettyPrinted(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ),
            let text = String(data: pretty, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return text
    }

    /// The blueprint name in a JSON document, if it parses and has one. Used to label the
    /// confirmation prompt with what is actually about to be sent.
    static func name(in json: String) -> String? {
        guard let object = try? parseObject(json) else { return nil }
        guard let name = object["name"] as? String else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The blueprint description in a JSON document, if it has one.
    static func description(in json: String) -> String? {
        guard let object = try? parseObject(json) else { return nil }
        guard let value = object["description"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The device group UUIDs a JSON document already scopes to.
    static func deviceGroupIDs(in json: String) -> [String] {
        guard
            let object = try? parseObject(json),
            let scope = object["scope"] as? [String: Any],
            let groups = scope["deviceGroups"] as? [Any]
        else { return [] }
        return groups.compactMap { $0 as? String }
    }

    /// How many steps a JSON document declares, for the summary line in the sheet.
    static func stepCount(in json: String) -> Int? {
        guard
            let object = try? parseObject(json),
            let steps = object["steps"] as? [Any]
        else { return nil }
        return steps.count
    }

    // MARK: - Internals

    private static func parseObject(_ json: String) throws -> [String: Any] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlueprintPayloadError.empty }
        guard let data = trimmed.data(using: .utf8) else { throw BlueprintPayloadError.notAnObject }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw BlueprintPayloadError.notJSON(error.localizedDescription)
        }

        guard let object = parsed as? [String: Any] else {
            throw BlueprintPayloadError.notAnObject
        }
        return object
    }

    private static func stripServerManagedKeys(_ object: inout [String: Any]) {
        for key in serverManagedKeys {
            object.removeValue(forKey: key)
        }
    }

    /// Writes the name and description supplied in the sheet's fields over whatever the JSON holds.
    /// A blank field is left alone, so the JSON's own value survives.
    private static func applyIdentity(name: String?, description: String?, to object: inout [String: Any]) {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            object["name"] = name
        }
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            object["description"] = description
        }
    }

    /// Catches a raw Apple declaration pasted in place of a blueprint.
    ///
    /// The two are easy to confuse: both are DDM JSON, but a declaration is what goes *inside* a
    /// blueprint's Custom Declarations component. Without this the failure surfaces as "needs a
    /// name", which sends the administrator looking for the wrong problem.
    private static func rejectAppleDeclaration(_ object: [String: Any]) throws {
        guard object["steps"] == nil, object["name"] == nil else { return }

        if let type = object["Type"] as? String, type.hasPrefix("com.apple.") {
            throw BlueprintPayloadError.looksLikeAppleDeclaration(type)
        }
        if object["Payload"] != nil && object["Identifier"] != nil {
            throw BlueprintPayloadError.looksLikeAppleDeclaration(object["Type"] as? String)
        }
    }

    private static func applyScope(_ scope: BlueprintScopeSelection, to object: inout [String: Any]) {
        switch scope {
        case .keepExisting:
            return
        case .groups(let ids):
            object["scope"] = ["deviceGroups": ids]
        case .unscoped:
            object["scope"] = ["deviceGroups": [String]()]
        }
    }

    private static func validateName(in object: [String: Any], required: Bool) throws {
        guard let raw = object["name"] else {
            if required { throw BlueprintPayloadError.missingName }
            return
        }
        guard let name = raw as? String else { throw BlueprintPayloadError.missingName }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlueprintPayloadError.missingName }
        guard name.count <= maxNameLength else {
            throw BlueprintPayloadError.nameTooLong(name.count)
        }
    }

    private static func validateScope(in object: [String: Any], required: Bool) throws {
        guard let raw = object["scope"] else {
            if required { throw BlueprintPayloadError.missingScope }
            return
        }
        guard let scope = raw as? [String: Any] else {
            throw BlueprintPayloadError.scopeNotAnObject
        }
        guard let groups = scope["deviceGroups"] else {
            throw BlueprintPayloadError.scopeNotAnObject
        }
        guard let array = groups as? [Any] else {
            throw BlueprintPayloadError.deviceGroupsNotStrings
        }
        guard array.allSatisfy({ $0 is String }) else {
            throw BlueprintPayloadError.deviceGroupsNotStrings
        }
        // An empty array is left alone on purpose. Jamf documents at least one group as
        // required; the server has the final say and its answer is what gets reported.
    }

    private static func validateSteps(in object: [String: Any], required: Bool) throws {
        guard let raw = object["steps"] else {
            if required { throw BlueprintPayloadError.missingSteps }
            return
        }
        guard let steps = raw as? [Any] else { throw BlueprintPayloadError.stepsNotAnArray }
        guard steps.count <= maxSteps else {
            throw BlueprintPayloadError.tooManySteps(steps.count)
        }

        for (index, step) in steps.enumerated() {
            guard let step = step as? [String: Any] else {
                throw BlueprintPayloadError.stepNotAnObject(index)
            }
            guard let components = step["components"] as? [Any] else {
                throw BlueprintPayloadError.componentsMissing(index)
            }
            guard !components.isEmpty else {
                throw BlueprintPayloadError.componentsEmpty(index)
            }
            guard components.count <= maxComponentsPerStep else {
                throw BlueprintPayloadError.tooManyComponents(index, components.count)
            }
        }
    }

    private static func serialise(_ object: [String: Any]) throws -> Data {
        do {
            // Slashes are left unescaped so any URL inside a payload stays readable on the wire.
            return try JSONSerialization.data(
                withJSONObject: object,
                options: [.withoutEscapingSlashes]
            )
        } catch {
            throw BlueprintPayloadError.serialisationFailed
        }
    }
}
