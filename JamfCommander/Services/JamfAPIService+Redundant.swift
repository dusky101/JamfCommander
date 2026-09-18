//
//  JamfAPIService+Redundant.swift
//  JamfCommander
//
//  The writes behind the Redundant audit.
//
//  Everything here changes a live Jamf instance, so three things hold without exception:
//
//  · **Nothing runs without the view having confirmed it.** This file is the hands, not the decision.
//  · **Packages are refused, not deleted.** `deletePackageRecord` exists to clean up a record this
//    app created moments earlier and could not upload to; it is deliberately not a general way to
//    remove packages, and the audit does not turn it into one.
//  · **Every item reports what actually happened.** A failure comes back as a failure with a reason
//    an administrator can act on — never swallowed, never reported as success.
//
//  Pacing matches every other bulk write in the app — batches of 5 with 0.5s between them — and one
//  item failing never stops the rest.
//

import Foundation

extension JamfAPIService {

    /// What the Redundant audit can do to what it lists.
    enum RedundantAction: Equatable, Sendable {
        /// Park something out of the way without destroying it. The audit's primary action, because
        /// it is the only one of the three that can be undone by hand afterwards.
        case moveToCategory(id: Int, name: String)
        /// Stop a policy running. Its scope, payload and Self Service entry all stay as they are.
        case disable
        /// Remove it from Jamf. There is no undo.
        case delete

        /// For confirmation copy and the results sheet title.
        var title: String {
            switch self {
            case .moveToCategory(_, let name): return "Move to \(name)"
            case .disable: return "Disable"
            case .delete: return "Delete"
            }
        }
    }

    /// Applies one action to every item given, and reports the real outcome of each.
    ///
    /// Items are processed in batches of 5 with a 0.5s gap, the same pacing as every other bulk
    /// write here — Jamf will throttle an unbounded fan-out, and a throttled delete is a change
    /// whose outcome nobody can be sure of.
    func applyRedundantAction(
        _ action: RedundantAction,
        to items: [RedundantItem]
    ) async -> [OperationResult] {
        var results: [OperationResult] = []

        let batchSize = 5
        let batches = stride(from: 0, to: items.count, by: batchSize).map {
            Array(items[$0..<min($0 + batchSize, items.count)])
        }

        for (batchIndex, batch) in batches.enumerated() {
            await withTaskGroup(of: OperationResult.self) { group in
                for item in batch {
                    group.addTask {
                        await self.apply(action, to: item)
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }

            if batchIndex < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        // Failures first: the point of the sheet is what did *not* work.
        return results.sorted { lhs, rhs in
            if lhs.success != rhs.success { return !lhs.success }
            return lhs.itemName.localizedCaseInsensitiveCompare(rhs.itemName) == .orderedAscending
        }
    }

    // MARK: - One item

    private func apply(_ action: RedundantAction, to item: RedundantItem) async -> OperationResult {
        guard item.kind.supportsActions else {
            return OperationResult(
                itemName: item.name,
                success: false,
                error: "Packages are listed for review only. Remove a package record in Jamf.",
                itemID: item.id
            )
        }

        guard let id = item.numericID else {
            return OperationResult(
                itemName: item.name,
                success: false,
                error: "This object's Jamf id could not be read, so it was left untouched.",
                itemID: item.id
            )
        }

        do {
            switch action {
            case .moveToCategory(let categoryID, let categoryName):
                switch item.kind {
                case .policy:
                    // Moves the Self Service category with it, so the two cannot drift apart.
                    try await movePolicy(id: id, toCategoryID: categoryID, categoryName: categoryName)
                case .profile:
                    try await moveProfile(id, toCategoryID: categoryID)
                case .package:
                    return Self.unsupported(item)
                }
                return OperationResult(
                    itemName: item.name,
                    success: true,
                    error: nil,
                    fromCategory: item.categoryName,
                    toCategory: categoryName,
                    itemID: item.id
                )

            case .disable:
                switch item.kind {
                case .policy:
                    try await setPolicyEnabled(id: id, enabled: false)
                case .profile:
                    // Not something to report vaguely: Jamf simply has no such state for a
                    // configuration profile. Removing its scope is the equivalent, and that is
                    // offered from the Profiles module.
                    return OperationResult(
                        itemName: item.name,
                        success: false,
                        error: "A configuration profile has no enabled state in Jamf. Remove its scope instead, from the Profiles module.",
                        itemID: item.id
                    )
                case .package:
                    return Self.unsupported(item)
                }
                return OperationResult(itemName: item.name, success: true, error: nil, itemID: item.id)

            case .delete:
                switch item.kind {
                case .policy:
                    try await deletePolicy(id: id)
                case .profile:
                    try await deleteProfile(id: id)
                case .package:
                    return Self.unsupported(item)
                }
                return OperationResult(itemName: item.name, success: true, error: nil, itemID: item.id)
            }
        } catch {
            return OperationResult(
                itemName: item.name,
                success: false,
                error: Self.failureReason(for: error),
                itemID: item.id
            )
        }
    }

    private static func unsupported(_ item: RedundantItem) -> OperationResult {
        OperationResult(
            itemName: item.name,
            success: false,
            error: "\(item.kind.singular) objects are not changed from the Redundant view.",
            itemID: item.id
        )
    }

    /// Why a write failed, phrased so an administrator can act on it.
    ///
    /// Carries no Jamf response body: bodies can echo tenant data, so the error is classified and
    /// the body discarded (root `CLAUDE.md`, invariant 4).
    nonisolated private static func failureReason(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "The change could not be sent to Jamf. Check your connection and try again."
        }

        switch apiError {
        case .authFailed:
            return "The Jamf session was refused. Reconnect to Jamf and try again."
        case .invalidURL:
            return "The Jamf instance URL is not valid. Check it in Settings."
        case .requestFailed:
            return "Jamf rejected the change. Check that this API client may update and delete this kind of object, then try again."
        case .httpError(let code):
            return "Jamf rejected the change (HTTP \(code)). Check in Jamf whether it was applied before retrying."
        case .decodingFailed:
            return "Jamf's response could not be read, so the outcome is unknown. Check the object in Jamf."
        case .unknown:
            return "Jamf reported an error. Check the object in Jamf before retrying."
        }
    }
}
