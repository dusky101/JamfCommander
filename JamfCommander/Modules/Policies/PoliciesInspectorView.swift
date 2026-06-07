//
//  PoliciesInspectorView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 18/01/2026.
//


import SwiftUI

struct PoliciesInspectorView: View {
    let policyId: Int
    @ObservedObject var api: JamfAPIService
    @Environment(\.dismiss) var dismiss
    
    // Data State
    @State private var jsonContent: String = "Loading..."
    @State private var policyDetail: PolicyDetailXML?
    // Phase 1 verification: parsed frequency / triggers / Self Service (read-only).
    @State private var editable: PolicyEditable?
    
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Edit State
    @State private var isEditingScope = false
    
    var body: some View {
        VStack(spacing: 0) {
            // --- HEADER ---
            ZStack {
                // Left
                HStack {
                    VStack(alignment: .leading) {
                        Text("Inspector")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "scroll.fill")
                                .font(.caption2)
                            Text("ID: \(policyId)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // Center
                Text(policyDetail?.general.name ?? "Loading...")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 400)
                
                // Right
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView().controlSize(.small).padding(.trailing, 8)
                    }
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // --- CONTENT ---
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Fetching Policy Data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                HSplitView {
                    // LEFT: Info & Scope
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                settingsSection
                                scopeSection
                            }
                            .padding()
                        }
                    }
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.02))
                    
                    // RIGHT: JSON Source
                    JSONEditorView(
                        title: "Raw Source (JSON)",
                        text: $jsonContent,
                        onSave: { _ in isSaving = false } // Mock save
                    )
                    .frame(minWidth: 400, maxWidth: .infinity)
                }
            }
        }
        .frame(width: 950, height: 700)
        .liquidGlass(cornerRadius: 16)
        .task {
            await loadData()
        }
    }
    
    var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Deployment Scope", systemImage: "scope")
                .font(.headline)
            
            if let scope = policyDetail?.scope {
                if scope.all_computers {
                    scopeBadge(title: "All Computers", subtitle: "Runs on fleet.", icon: "globe", color: .green)
                } else {
                    scopeBadge(title: "Targeted", subtitle: "Restricted scope.", icon: "target", color: .orange)
                }
                
                if !scope.all_computers, let computers = scope.computers {
                    Text("TARGETS (\(computers.count))")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary).padding(.top, 8)
                    ForEach(computers) { computer in
                        HStack {
                            Image(systemName: "desktopcomputer").foregroundColor(.secondary)
                            Text(computer.name).font(.subheadline)
                            Spacer()
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    func scopeBadge(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).padding(.trailing, 4)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).opacity(0.8)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 1))
    }
    
    // MARK: - Parsed Settings (read-only, Phase 1 verification)

    @ViewBuilder
    var settingsSection: some View {
        if let editable {
            VStack(alignment: .leading, spacing: 24) {
                Text("Parsed policy settings — read-only")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                InfoSection(title: "Execution", icon: "clock.arrow.circlepath") {
                    InfoRow(label: "Frequency", value: editable.frequency.displayName)
                    InfoRow(
                        label: "Custom Trigger",
                        value: editable.triggers.hasCustomTrigger ? editable.triggers.trimmedCustomTrigger : "None"
                    )
                }

                InfoSection(title: "Triggers", icon: "bolt.fill") {
                    InfoRow(label: "Recurring Check-in", value: onOff(editable.triggers.checkin))
                    InfoRow(label: "Enrolment Complete", value: onOff(editable.triggers.enrollmentComplete))
                    InfoRow(label: "Login", value: onOff(editable.triggers.login))
                    InfoRow(label: "Logout", value: onOff(editable.triggers.logout))
                    InfoRow(label: "Network State Change", value: onOff(editable.triggers.networkStateChanged))
                    InfoRow(label: "Startup", value: onOff(editable.triggers.startup))
                }

                InfoSection(title: "Self Service", icon: "bag.fill") {
                    InfoRow(label: "Available", value: editable.selfService.useForSelfService ? "Yes" : "No")
                    InfoRow(
                        label: "Display Name",
                        value: editable.selfService.displayName.isEmpty ? "—" : editable.selfService.displayName
                    )
                    InfoRow(label: "Categories", value: "\(editable.selfService.categories.count)")
                    InfoRow(label: "Feature on Main Page", value: editable.selfService.featureOnMainPage ? "Yes" : "No")
                    InfoRow(label: "Icon", value: iconSummary(editable.selfService.icon))
                }
            }
        }
    }

    private func onOff(_ value: Bool) -> String { value ? "On" : "Off" }

    private func iconSummary(_ icon: SelfServiceIcon?) -> String {
        guard let icon, icon.isAssigned else { return "None" }
        if let filename = icon.filename, !filename.isEmpty { return filename }
        if let id = icon.id { return "ID \(id)" }
        return "Assigned"
    }

    func loadData() async {
        do {
            async let fetchedJSON = api.fetchPolicyJSON(id: policyId)
            async let fetchedDetail = api.fetchPolicyDetail(id: policyId)
            async let fetchedEditable = api.fetchPolicyEditable(id: policyId)
            let (json, detail, editablePolicy) = try await (fetchedJSON, fetchedDetail, fetchedEditable)
            self.jsonContent = json
            self.policyDetail = detail
            self.editable = editablePolicy
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}
