//
//  ScopeTargetProbe.swift
//  JamfCommander
//
//  Answers one question about a Jamf scope — "does this target anything at all?" — without modelling
//  what a target looks like.
//
//  Why this exists. `PolicyScope` and `ScopeInfo` model the three targets this app has always needed:
//  `all_computers`, computers, and computer groups. Jamf's Targets tab also offers **buildings** and
//  **departments**, which those types do not decode. That was harmless while the app only displayed
//  scope. It stopped being harmless the moment the Redundant audit put a Delete button next to the
//  words "not scoped": a policy targeted at a building would have been reported as reaching nothing.
//
//  The obvious fix — add `buildings` and `departments` to the models — needs the exact JSON shape of
//  a scope entry, which this project has never read back and which `docs/JAMF_API_REFERENCE.md` does
//  not record. Guessing it is precisely what invariant 2 forbids, and a wrong guess fails silently:
//  the field decodes to nil and the policy is reported as unscoped again.
//
//  So this does not guess. It walks the scope object generically and asks whether any target-bearing
//  key holds anything. It needs to know only two things, both of which are Jamf's own vocabulary and
//  neither of which is a shape:
//
//  · `limit_to_users`, `limitations` and `exclusions` **narrow** a scope; they never create one. A
//    policy limited to a user group but targeted at nothing still reaches nothing.
//  · Everything else under `scope` is a target. A `true` boolean (`all_computers`) or a non-empty
//    collection means something is targeted.
//
//  A target type Jamf adds tomorrow is therefore counted correctly the day it appears, and the
//  failure mode is the safe one: anything it cannot interpret is not reported as redundant.
//

import Foundation

/// A decoded Jamf `scope` object, reduced to the single fact the audit needs.
struct ScopeTargetProbe: Decodable, Hashable, Sendable {
    /// Whether the scope targets anything this instance of Jamf would deploy to.
    let targetsAnything: Bool

    /// Keys under `scope` that narrow the scope rather than create one.
    private static let narrowingKeys: Set<String> = [
        "limit_to_users",
        "limitations",
        "exclusions",
    ]

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: DynamicCodingKey.self) else {
            // Not an object at all — nothing can be read from it, so claim nothing.
            targetsAnything = false
            return
        }

        var found = false
        for key in container.allKeys where !Self.narrowingKeys.contains(key.stringValue) {
            guard let value = try? container.decode(ProbedValue.self, forKey: key) else { continue }
            if value.holdsSomething {
                found = true
                break
            }
        }
        targetsAnything = found
    }

    /// For a caller that has no JSON to decode from.
    init(targetsAnything: Bool) {
        self.targetsAnything = targetsAnything
    }
}

// MARK: - Generic JSON shapes

/// A JSON value reduced to the shape questions this file asks. Decoding never throws: an
/// unrecognised value becomes `.opaque` and counts as nothing, so a shape nobody anticipated can
/// never be mistaken for a target.
private enum ProbedValue: Decodable {
    case flag(Bool)
    case list([ProbedValue])
    case object([String: ProbedValue])
    case opaque

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [ProbedValue] = []
            while !unkeyed.isAtEnd {
                // `ProbedValue` accepts every JSON value, so this always advances the container —
                // there is no shape that could spin this loop.
                items.append(try unkeyed.decode(ProbedValue.self))
            }
            self = .list(items)
            return
        }

        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: ProbedValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try? keyed.decode(ProbedValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if let single = try? decoder.singleValueContainer(), let flag = try? single.decode(Bool.self) {
            self = .flag(flag)
            return
        }

        self = .opaque
    }

    /// Whether this value amounts to a target being set.
    ///
    /// The nested-object case is not hypothetical: Jamf's Classic API renders a repeatable element
    /// as an array when there are several children and as a bare object when there is exactly one
    /// (the same quirk `decodeFlexibleArray` exists for), so a scope with one targeted building can
    /// arrive as an object rather than a one-item array.
    var holdsSomething: Bool {
        switch self {
        case .flag(let value):
            return value
        case .list(let items):
            return !items.isEmpty
        case .object(let members):
            return members.values.contains { $0.holdsSomething }
        case .opaque:
            return false
        }
    }
}

/// A `CodingKey` that accepts whatever key the payload actually carries, so a container's keys can
/// be enumerated rather than declared up front.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
