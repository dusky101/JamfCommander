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
    @State private var editable: PolicyEditable?
    @State private var categories: [Category] = []

    @State private var isLoading = true
    @State private var errorMessage: String?

    // Edit State
    @State private var isEditingScope = false

    // View State
    @State private var selectedTab: InspectorTab = .settings

    enum InspectorTab: String, CaseIterable, Identifiable {
        case settings, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .settings: return "Settings"
            case .advanced: return "Advanced (JSON)"
            }
        }
    }
    
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
            } else if let errorMessage {
                errorView(errorMessage)
            } else {
                // Tab selector — Settings (editable) vs Advanced (read-only JSON).
                HStack {
                    Picker("View", selection: $selectedTab) {
                        ForEach(InspectorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                switch selectedTab {
                case .settings:
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .leading, spacing: 24) {
                                if let editable {
                                    PolicyEditorView(
                                        api: api,
                                        policyId: policyId,
                                        policyName: editable.name,
                                        initialFrequency: editable.frequency,
                                        initialTriggers: editable.triggers,
                                        onSaved: { await reload() }
                                    )

                                    PolicySelfServiceEditorView(
                                        api: api,
                                        policyId: policyId,
                                        policyName: editable.name,
                                        categories: categories,
                                        initialSettings: editable.selfService,
                                        onSaved: { await reload() }
                                    )
                                }
                                scopeSection
                            }
                            .frame(maxWidth: 680)
                            Spacer(minLength: 0)
                        }
                        .padding()
                    }
                    .frame(maxHeight: .infinity)

                case .advanced:
                    // Raw JSON — read-only (no onSave ⇒ no edit affordance).
                    JSONEditorView(
                        title: "Raw Source (JSON)",
                        text: $jsonContent
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 950, height: 700)
        .appBackground()
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

    /// Shown when the policy detail can't be loaded. Surfaces a calm message plus the underlying
    /// reason (selectable) so a failure is never silent — the raw JSON remains viewable in Jamf.
    func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load this policy")
                .font(.headline)
            Text("The policy details couldn't be read. The reason is shown below; you can still view the raw record in the Jamf Pro console.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            ScrollView {
                Text(message)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .cornerRadius(8)
            Button("Try Again") {
                Task {
                    isLoading = true
                    await loadData()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 520)
        .frame(maxHeight: .infinity)
        .padding()
    }

    func loadData() async {
        errorMessage = nil
        do {
            async let fetchedJSON = api.fetchPolicyJSON(id: policyId)
            async let fetchedDetail = api.fetchPolicyDetail(id: policyId)
            async let fetchedEditable = api.fetchPolicyEditable(id: policyId)
            // Categories are non-critical: a failure must not blank the inspector.
            async let fetchedCategories: [Category] = (try? await api.fetchCategories()) ?? []
            let (json, detail, editablePolicy, cats) = try await (fetchedJSON, fetchedDetail, fetchedEditable, fetchedCategories)
            self.jsonContent = json
            self.policyDetail = detail
            self.editable = editablePolicy
            self.categories = cats
            self.isLoading = false
        } catch {
            // Never swallow silently — surface the reason in-UI and log a developer line. The
            // error is a decode/transport failure, not an API body, so it carries no secrets.
            print("PoliciesInspectorView: failed to load policy \(policyId): \(error)")
            self.errorMessage = "\(error)"
            self.isLoading = false
        }
    }

    /// Refreshes the inspector's data after an in-place edit, without flashing the full
    /// loading state. On failure the last good data is retained.
    func reload() async {
        do {
            async let fetchedJSON = api.fetchPolicyJSON(id: policyId)
            async let fetchedDetail = api.fetchPolicyDetail(id: policyId)
            async let fetchedEditable = api.fetchPolicyEditable(id: policyId)
            async let fetchedCategories: [Category] = (try? await api.fetchCategories()) ?? []
            let (json, detail, editablePolicy, cats) = try await (fetchedJSON, fetchedDetail, fetchedEditable, fetchedCategories)
            self.jsonContent = json
            self.policyDetail = detail
            self.editable = editablePolicy
            self.categories = cats
        } catch {
            // Keep the last good data on a refresh failure.
        }
    }
}
