//
//  ABMLog.swift
//  JamfCommander
//
//  Diagnostic logging for Apple Business Manager fetches.
//

import Foundation
import OSLog

/// Progress and failure logging for the Apple Business Manager integration.
///
/// CFNetwork fills the console with its own transport noise during a bulk fetch, which says nothing
/// about which device is being fetched or why one failed. These messages are tagged `[ABM]` so they
/// can be filtered out of it in Xcode's console.
///
/// **Never log a token, a client secret, a private key, or a raw response body.** Serial numbers and
/// endpoint paths are fine; they are already visible in the UI and in CFNetwork's own output.
enum ABMLog {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcoliff.JamfCommander",
        category: "ABM"
    )

    static func info(_ message: String) {
        logger.info("[ABM] \(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("[ABM] \(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("[ABM] \(message, privacy: .public)")
    }
}
