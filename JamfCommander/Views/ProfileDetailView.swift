//
//  ProfileDetailView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//


import SwiftUI

struct ProfileDetailView: View {
    let profileId: Int
    @ObservedObject var api: JamfAPIService
    @Environment(\.dismiss) var dismiss
    
    @State private var profileContent: String = "Loading..."
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Profile Inspector")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            ScrollView {
                Text(profileContent)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .textSelection(.enabled) // Allows user to copy the XML
            }
        }
        .frame(width: 600, height: 500)
        .liquidGlass(.panel)
        .task {
            do {
                let content = try await api.fetchProfileDetails(id: profileId)
                profileContent = content
            } catch {
                profileContent = "Error loading profile details."
            }
        }
    }
}