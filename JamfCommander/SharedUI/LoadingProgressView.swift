//
//  LoadingProgressView.swift
//  JamfCommander
//
//  Created by Marc Oliff on 07/03/2026.
//

import SwiftUI

struct LoadingProgressView: View {
    var message: String = "Loading Jamf data..."
    
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "command.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
                .symbolEffect(.pulse, options: .repeating, value: animateIcon)
            
            Text(message)
                .font(.headline)
                .foregroundColor(.primary)
            
            ProgressView()
                .controlSize(.large)
            
            Text("Fetching computers, policies, profiles and scripts...")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { animateIcon = true }
    }
}
