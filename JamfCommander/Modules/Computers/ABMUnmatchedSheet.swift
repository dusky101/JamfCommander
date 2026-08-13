//
//  ABMUnmatchedSheet.swift
//  JamfCommander
//
//  Macs Apple Business Manager has assigned to Jamf Pro that Jamf does not know about.
//

import SwiftUI

/// Lists Macs assigned to the Jamf Pro MDM server in Apple Business Manager that have no record in
/// Jamf's inventory.
///
/// The Computers table is built outward from Jamf, so these have nowhere to appear there — but they
/// are the asset management gap worth chasing: hardware the organisation owns and Apple has assigned
/// to Jamf, that nothing is managing. Usually new stock not yet deployed, or a machine wiped and
/// never re-enrolled.
struct ABMUnmatchedSheet: View {

    let devices: [ABMDeviceRecord]
    let lifecycleYears: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Assigned in ABM, Not in Jamf")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("^[\(devices.count) Mac](inflect: true) assigned to your Jamf Pro MDM server in Apple Business Manager with no record in Jamf's inventory. Usually stock that has not been deployed yet, or a device wiped and never re-enrolled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if devices.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("Every Mac assigned in Apple Business Manager is enrolled in Jamf.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                deviceTable
            }

            HStack {
                Button {
                    copySerials()
                } label: {
                    Label("Copy Serials", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(devices.isEmpty)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 760, height: 480)
        .appBackground()
    }

    private var deviceTable: some View {
        Table(devices) {
            TableColumn("Serial") { device in
                Text(device.serialNumber)
                    .font(.caption)
                    .fontDesign(.monospaced)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Model") { device in
                Text(device.attributes.deviceModel ?? "—")
                    .lineLimit(1)
            }
            .width(min: 180, ideal: 230)

            TableColumn("Purchased") { device in
                Text(dateText(device.purchaseDate, whenMissing: "Unknown"))
                    .font(.caption)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Warranty Ends") { device in
                Text(dateText(device.warrantyEndDate))
                    .font(.caption)
                    .foregroundColor(warrantyColour(for: device))
            }
            .width(min: 110, ideal: 130)

            TableColumn("Order Number") { device in
                Text(device.attributes.orderNumber ?? "—")
                    .font(.caption)
                    .lineLimit(1)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Added to ABM") { device in
                Text(dateText(device.attributes.addedToOrgDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .width(min: 100, ideal: 120)
        }
    }

    /// Wrapped rather than passed as `.map(ComputerFleetRow.dateText)`: a bare function reference
    /// escapes the main actor, where the shared formatter lives.
    private func dateText(_ date: Date?, whenMissing placeholder: String = "—") -> String {
        guard let date else { return placeholder }
        return ComputerFleetRow.dateText(date)
    }

    private func warrantyColour(for device: ABMDeviceRecord) -> Color {
        guard let end = device.warrantyEndDate else { return .primary }
        return end < Date() ? .orange : .primary
    }

    /// Serials are what you paste into Jamf, a spreadsheet or a supplier query, so they are the one
    /// thing worth putting on the clipboard.
    private func copySerials() {
        let serials = devices.map(\.serialNumber).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serials, forType: .string)
    }
}
