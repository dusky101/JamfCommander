//
//  SettingsPlatformSection.swift
//  JamfCommander
//
//  Created by Marc Oliff on 19/09/2026.
//

import SwiftUI

/// Outcome of the last Platform API connection test.
enum PlatformTestState: Equatable {
    case idle
    case testing
    case succeeded
    case failed(String)
}

/// The Platform API Gateway credentials that Blueprints needs, and the test that proves them.
///
/// A separate integration from the Jamf Pro client above: created in Jamf Account, scoped to a
/// platform environment, and region-locked. A Jamf Pro API client cannot reach this API at all.
struct SettingsPlatformSection: View {
    /// Needed only for "Test Connection"; the credential fields themselves are plain `@AppStorage`.
    @ObservedObject var api: JamfAPIService

    /// A result only describes the credentials it was obtained with, so this is cleared the moment
    /// any of them changes — see `invalidateResult()`.
    @State private var testState: PlatformTestState = .idle

    /// Held so a test still in flight can be discarded rather than allowed to report against
    /// credentials that have since been edited.
    @State private var testTask: Task<Void, Never>?

    @AppStorage(PlatformCredentialsStore.regionKey) private var platformRegion = PlatformRegion.eu.rawValue
    @AppStorage(PlatformCredentialsStore.environmentIdKey) private var platformEnvironmentId = ""
    @AppStorage(PlatformCredentialsStore.clientIdKey) private var platformClientId = ""
    @AppStorage(PlatformCredentialsStore.clientSecretKey) private var platformClientSecret = ""

    /// All three values are required, so testing is offered only once none of them is blank.
    private var canTest: Bool {
        !platformEnvironmentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !platformClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !platformClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.secondary)
                Text("Platform API — Blueprints")
                    .font(.headline)
            }

            Text("A separate integration, created in Jamf Account rather than Jamf Pro and scoped to a platform environment. A Jamf Pro API client cannot reach this API. Grant it the blueprints and device-groups capabilities.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading) {
                Text("Region")
                    .font(.caption)
                Picker("Region", selection: $platformRegion) {
                    ForEach(PlatformRegion.allCases) { region in
                        Text(region.displayName).tag(region.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Platform API region")
                Text("Must match where your Jamf instances are hosted — access tokens are region-locked.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Environment ID")
                    .font(.caption)
                TextField("e.g. cda24521-f23b-4f27-a9ff-32c89fb6feeb", text: $platformEnvironmentId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Platform environment ID")
                Text("Copied from the Integration details panel in Jamf Account.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading) {
                Text("Client ID")
                    .font(.caption)
                TextField("Integration client ID", text: $platformClientId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Platform API client ID")
            }

            VStack(alignment: .leading) {
                Text("Client Secret")
                    .font(.caption)
                SecureField("Paste Secret Here", text: $platformClientSecret)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Platform API client secret")
            }

            HStack(spacing: 10) {
                Button(action: testConnection) {
                    if testState == .testing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        }
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canTest || testState == .testing)
                .help("Request a token and list one blueprint, to confirm the credentials, region and environment ID")

                Spacer()
            }

            testResult
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        // Each of these is part of what a test result describes. The region most of all: tokens are
        // region-locked, so a result obtained in one region says nothing about another.
        .onChange(of: platformRegion) { invalidateResult() }
        .onChange(of: platformEnvironmentId) { invalidateResult() }
        .onChange(of: platformClientId) { invalidateResult() }
        .onChange(of: platformClientSecret) { invalidateResult() }
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .idle, .testing:
            EmptyView()
        case .succeeded:
            Label("Connected. Blueprints are reachable.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func testConnection() {
        testTask?.cancel()
        testState = .testing

        testTask = Task {
            do {
                try await api.verifyPlatformConnection()
                // A cancelled test was started against credentials that have since changed, so its
                // answer is meaningless. Discard it rather than reporting it — and never retry it.
                guard !Task.isCancelled else { return }
                testState = .succeeded
            } catch {
                guard !Task.isCancelled else { return }
                testState = .failed(error.localizedDescription)
            }
        }
    }

    /// Drops the last result, and any test still running, because the credentials it applied to no
    /// longer exist. Without this a green "Connected" survives an edit to the client secret.
    private func invalidateResult() {
        testTask?.cancel()
        testTask = nil
        testState = .idle
    }
}
