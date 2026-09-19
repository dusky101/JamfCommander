//
//  EstateScanGate.swift
//  JamfCommander
//
//  Holds a sidebar move until the estate scan finishes, then makes it.
//
//  The Dashboard puts its tiles up before it starts reading every policy, so it looks finished
//  while the Unused tile is still counting. Moving on at that moment used to throw the scan away —
//  it no longer does, and whichever module you land on joins the scan already running rather than
//  starting a second. But it still *waits*, and waiting inside Installomator with no explanation
//  reads as "Installomator is slow" rather than "the estate is still being read".
//
//  So the wait is moved somewhere it can be explained, and the move is made for you when the scan
//  lands. Staying put is the other answer; there is deliberately no "go anyway", because going
//  anyway would wait for exactly the same scan with less to look at.
//

import SwiftUI

struct EstateScanGate: View {
    /// Where the sidebar was trying to go, named so the wait has a point.
    let destination: AppModule

    /// Where you are now, so the way out says where staying put leaves you. Not always the
    /// Dashboard: a Refresh from the Unused module starts the same scan.
    let origin: AppModule

    /// Give up on the move and stay where you are.
    let onStayHere: () -> Void

    @State private var animateIcon = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeating, value: animateIcon)

                Text("Still reading every policy")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("The Unused count is not finished yet. \(destination.rawValue) opens on its own the moment it is — it needs the same read, so leaving now would only wait somewhere less obvious.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 220)

                Button("Stay on \(origin.rawValue)") { onStayHere() }
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 2)
            }
            .padding(28)
            .frame(width: 420)
            .appBarBackground(cornerRadius: 18)
        }
        // Swallows every click underneath, which is the point.
        .contentShape(Rectangle())
        .onAppear { animateIcon = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Still reading every policy. \(destination.rawValue) will open when the read finishes.")
    }
}
