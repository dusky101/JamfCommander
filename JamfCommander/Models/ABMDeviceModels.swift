//
//  ABMDeviceModels.swift
//  JamfCommander
//
//  Apple Business Manager device, warranty and derived asset values.
//

import Foundation

// MARK: - Timestamps

/// Apple Business Manager is inconsistent about fractional seconds: `addedToOrgDateTime` carries them,
/// `orderDateTime` and the coverage dates do not. A single `ISO8601DateFormatter` fails on one or the
/// other, which shows up as fields that are intermittently and inexplicably blank.
nonisolated enum ABMDate {

    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return withFractional.date(from: value) ?? plain.date(from: value)
    }
}

// MARK: - Device

/// How a device entered the organisation. This decides whether `orderDateTime` can be believed.
nonisolated enum ABMPurchaseSourceType: String, Codable, Sendable {
    case apple = "APPLE"
    case reseller = "RESELLER"
    case manuallyAdded = "MANUALLY_ADDED"
    case unknown

    init(rawValue: String) {
        switch rawValue.uppercased() {
        case "APPLE": self = .apple
        case "RESELLER": self = .reseller
        case "MANUALLY_ADDED": self = .manuallyAdded
        default: self = .unknown
        }
    }

    /// Whether `orderDateTime` records a genuine purchase.
    ///
    /// For a device added through Apple Configurator the order date is fabricated from the add
    /// operation — one sampled device ordered on 16 January had been added to the organisation on the
    /// 15th. Presenting that as a purchase date would put a wrong number in front of finance.
    var hasTrustworthyOrderDate: Bool {
        self == .apple || self == .reseller
    }

    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .reseller: return "Reseller"
        case .manuallyAdded: return "Added manually"
        case .unknown: return "Unknown"
        }
    }
}

/// The `attributes` block of an `orgDevices` record. Everything is optional: Apple omits fields
/// rather than sending nulls, and the attribute set has changed since the API launched.
nonisolated struct ABMDeviceAttributes: Codable, Hashable, Sendable {
    let serialNumber: String?
    let productFamily: String?
    /// The marketing name, e.g. "MacBook Pro (16-inch, Nov 2024)". Better formatted than Jamf's.
    let deviceModel: String?
    /// The board identifier, e.g. "Mac16,5". Useful for grouping.
    let productType: String?
    let deviceCapacity: String?
    let color: String?
    let partNumber: String?
    let orderNumber: String?
    let orderDateTime: String?
    let purchaseSourceType: String?
    let purchaseSourceId: String?
    let addedToOrgDateTime: String?
    let releasedFromOrgDateTime: String?
    let status: String?
    let updatedDateTime: String?

    var isMac: Bool { productFamily == "Mac" }

    var purchaseSource: ABMPurchaseSourceType {
        ABMPurchaseSourceType(rawValue: purchaseSourceType ?? "")
    }

    var orderDate: Date? { ABMDate.parse(orderDateTime) }
    var addedToOrgDate: Date? { ABMDate.parse(addedToOrgDateTime) }
    /// Non-nil means the device has left the organisation in ABM.
    var releasedFromOrgDate: Date? { ABMDate.parse(releasedFromOrgDateTime) }
}

nonisolated struct ABMDeviceEnvelope: Codable, Hashable, Sendable {
    let id: String
    let type: String?
    let attributes: ABMDeviceAttributes?
}

// MARK: - Coverage

/// One AppleCare or Limited Warranty record. Devices may hold more than one.
nonisolated struct ABMCoverage: Codable, Hashable, Sendable {
    /// "Limited Warranty", "AppleCare", "AppleCare+". Renamed from the API's `description` so it does
    /// not collide with `CustomStringConvertible`.
    let coverageDescription: String?
    let startDateTime: String?
    let endDateTime: String?
    let status: String?
    let agreementNumber: String?
    let isRenewable: Bool?
    let isCanceled: Bool?
    let paymentType: String?
    let contractCancelDateTime: String?

    enum CodingKeys: String, CodingKey {
        case coverageDescription = "description"
        case startDateTime, endDateTime, status, agreementNumber
        case isRenewable, isCanceled, paymentType, contractCancelDateTime
    }

    var startDate: Date? { ABMDate.parse(startDateTime) }
    var endDate: Date? { ABMDate.parse(endDateTime) }
    var isActive: Bool { status?.uppercased() == "ACTIVE" }
}

nonisolated struct ABMCoverageEnvelope: Codable, Hashable, Sendable {
    let id: String
    let type: String?
    let attributes: ABMCoverage?
}

// MARK: - Derived values

/// Where a purchase date came from. Presenting an inferred date identically to a known one would be
/// misleading, and this data ends up informing finance and refresh planning.
nonisolated enum ABMPurchaseDateSource: String, Codable, Sendable {
    case orderDateApple
    case orderDateReseller
    case warrantyStart
    case addedToOrg
    case unknown

    /// Whether the date is taken from a real purchase record rather than inferred.
    var isReliable: Bool {
        self == .orderDateApple || self == .orderDateReseller
    }

    var displayName: String {
        switch self {
        case .orderDateApple: return "Apple order date"
        case .orderDateReseller: return "Reseller order date"
        case .warrantyStart: return "Inferred from warranty start"
        case .addedToOrg: return "Inferred from date added to ABM"
        case .unknown: return "Unknown"
        }
    }

    /// The value written to the CSV export, matching the proof-of-concept extract's column.
    var exportValue: String {
        switch self {
        case .orderDateApple: return "orderDateTime (APPLE)"
        case .orderDateReseller: return "orderDateTime (RESELLER)"
        case .warrantyStart: return "warrantyStart (inferred)"
        case .addedToOrg: return "addedToOrg (weak)"
        case .unknown: return "unknown"
        }
    }
}

/// What is known about a device's warranty. "No record" and "not in ABM" are deliberately different
/// things and are never collapsed: the first is normal for an older machine, the second is an asset
/// management gap worth investigating.
nonisolated enum ABMWarrantyState: Sendable, Hashable {
    case active(end: Date?)
    case expired(end: Date?)
    /// In ABM, but the coverage array came back empty.
    case noRecord
    /// The coverage request itself failed, so nothing is known either way.
    case unavailable
}

// MARK: - Joined record

/// One Mac as Apple Business Manager knows it, with its coverage and the time it was fetched.
///
/// This is what the cache stores and what the Computers views read. Derived values are computed here
/// rather than in a view, so the inspector, the table and the CSV export cannot disagree.
nonisolated struct ABMDeviceRecord: Codable, Hashable, Sendable, Identifiable {
    let serialNumber: String
    let attributes: ABMDeviceAttributes
    /// `nil` means the coverage request failed; `[]` means the device genuinely has no coverage
    /// records. Collapsing the two would report a network problem as "out of warranty".
    let coverage: [ABMCoverage]?
    let fetchedAt: Date

    var id: String { serialNumber }

    // MARK: Coverage selection

    /// The record representing current cover.
    ///
    /// Zellis holds only Limited Warranties today, one per device — but Apple's documentation and
    /// other tenants show several coverage records per device, so this handles an array: prefer an
    /// `ACTIVE` record with the latest end date, otherwise fall back to the latest record of any
    /// status so the UI can show when cover lapsed rather than showing nothing.
    var selectedCoverage: ABMCoverage? {
        guard let coverage, !coverage.isEmpty else { return nil }
        let active = coverage.filter(\.isActive)
        let pool = active.isEmpty ? coverage : active
        return pool.max { lhs, rhs in
            (lhs.endDate ?? .distantPast) < (rhs.endDate ?? .distantPast)
        }
    }

    var warrantyState: ABMWarrantyState {
        guard coverage != nil else { return .unavailable }
        guard let selected = selectedCoverage else { return .noRecord }
        return selected.isActive ? .active(end: selected.endDate) : .expired(end: selected.endDate)
    }

    var warrantyEndDate: Date? { selectedCoverage?.endDate }

    var isInWarranty: Bool {
        if case .active = warrantyState { return true }
        return false
    }

    /// Whole days until cover ends. Negative once it has lapsed, `nil` when there is no end date.
    func daysRemaining(from reference: Date = Date()) -> Int? {
        guard let end = warrantyEndDate else { return nil }
        return Calendar.current.dateComponents([.day], from: reference, to: end).day
    }

    // MARK: Purchase date

    /// The purchase date and where it came from, per the rules in `ABMPurchaseSourceType`.
    var purchase: (date: Date?, source: ABMPurchaseDateSource) {
        let attributeSource = attributes.purchaseSource

        if attributeSource.hasTrustworthyOrderDate, let orderDate = attributes.orderDate {
            return (orderDate, attributeSource == .apple ? .orderDateApple : .orderDateReseller)
        }

        // For a manually added device the warranty start reflects activation, which is a sound proxy.
        if let warrantyStart = selectedCoverage?.startDate {
            return (warrantyStart, .warrantyStart)
        }

        if let added = attributes.addedToOrgDate {
            return (added, .addedToOrg)
        }

        return (nil, .unknown)
    }

    var purchaseDate: Date? { purchase.date }
    var purchaseDateSource: ABMPurchaseDateSource { purchase.source }

    // MARK: Lifecycle

    /// Purchase date plus the configured interval. Not an Apple concept and not held by Jamf, so it
    /// is calculated. `Calendar` handles 29 February by clamping to the 28th.
    func lifecycleDate(years: Int) -> Date? {
        guard let purchaseDate else { return nil }
        return Calendar.current.date(byAdding: .year, value: years, to: purchaseDate)
    }

    func isPastLifecycle(years: Int, from reference: Date = Date()) -> Bool {
        guard let lifecycle = lifecycleDate(years: years) else { return false }
        return lifecycle < reference
    }

    /// Non-nil when ABM says the device has left the organisation. Shown rather than hidden: Jamf
    /// still managing a machine ABM has released is a discrepancy worth seeing.
    var releasedFromOrgDate: Date? { attributes.releasedFromOrgDate }
}
