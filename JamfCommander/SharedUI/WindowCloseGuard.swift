//
//  WindowCloseGuard.swift
//  JamfCommander
//
//  "Close this and you lose what you have entered" — asked before the window actually goes.
//
//  Shared because every window this app is growing has the same problem. The Installomator
//  deployment window is the first caller; the Blueprints editor and the package upload are both
//  named as candidates in `docs/roadmap/SHEET_NAVIGATION.md` and both hold work worth losing.
//
//  ## Why this is not just `.alert`
//
//  `.alert` shows the question perfectly well, and it is what this uses. What it cannot do is
//  *stop* the close: every SwiftUI hook fires once the window has already gone, so by the time
//  `onDisappear` runs there is nothing left to warn about. macOS asks exactly one question before
//  closing a window — `NSWindowDelegate.windowShouldClose(_:)` — and there is no SwiftUI spelling
//  of it. Answering that question is the whole of the AppKit here; the dialogue above it is an
//  ordinary alert.
//
//  `NSWindow.isDocumentEdited` is not an alternative either. It draws the dark dot in the close
//  button and prompts for nothing.
//
//  ## Why the delegate is chained rather than replaced
//
//  A `Window` scene already has a delegate of SwiftUI's own, and taking it over breaks everything
//  SwiftUI uses it for. `CloseGuardDelegate` answers `windowShouldClose(_:)` itself and forwards
//  every other message to whoever was there first.
//

import SwiftUI
import AppKit

extension View {

    /// Asks before this view's window closes, when there is something to lose.
    ///
    /// - Parameters:
    ///   - isEnabled: whether there is anything worth warning about. `false` closes silently — a
    ///     window somebody opened and shut again should not argue with them, and a dialogue that
    ///     appears every time is the one people learn to dismiss without reading.
    ///   - title: the alert's title. A question, because it is one.
    ///   - message: what is lost.
    ///   - discardTitle: the destructive button's label. Say what goes, not "OK".
    ///   - onDiscard: called when the reader confirms, just before the window is allowed to close.
    ///     Optional — the close happens either way.
    func confirmWindowClose(
        when isEnabled: Bool,
        title: String,
        message: String,
        discardTitle: String = "Discard",
        onDiscard: (() -> Void)? = nil
    ) -> some View {
        modifier(
            WindowCloseGuard(
                isEnabled: isEnabled,
                title: title,
                message: message,
                discardTitle: discardTitle,
                onDiscard: onDiscard
            )
        )
    }
}

// MARK: - The modifier

private struct WindowCloseGuard: ViewModifier {
    let isEnabled: Bool
    let title: String
    let message: String
    let discardTitle: String
    let onDiscard: (() -> Void)?

    @State private var isAsking = false
    /// Set while the reader's answer is being acted on, so the close this modifier performs itself
    /// is not intercepted a second time and asked about again.
    @State private var isClosingDeliberately = false

    func body(content: Content) -> some View {
        content
            .background(
                WindowCloseInterceptor(
                    shouldClose: {
                        // Nothing to lose, or the reader has already said to discard it.
                        guard isEnabled, !isClosingDeliberately else { return true }
                        isAsking = true
                        return false
                    }
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            )
            .alert(title, isPresented: $isAsking) {
                Button("Keep Editing", role: .cancel) { }
                Button(role: .destructive) {
                    onDiscard?()
                    isClosingDeliberately = true
                    // The window refused the first close, so it has to be asked again — and this
                    // time the guard above lets it through.
                    NSApp.keyWindow?.close()
                } label: {
                    // White, explicitly. A `.destructive` button in this app renders its label in
                    // red *on* the red fill, which is legible in a screenshot and not on a screen.
                    // The role stays — it is what tells VoiceOver this is the destructive choice,
                    // and what puts the button where macOS expects it.
                    Text(discardTitle)
                        .foregroundStyle(.white)
                }
            } message: {
                Text(message)
            }
    }
}

// MARK: - The one AppKit question

/// A zero-sized view whose only job is to reach the `NSWindow` it ends up in and answer
/// `windowShouldClose(_:)` on its behalf.
private struct WindowCloseInterceptor: NSViewRepresentable {
    let shouldClose: () -> Bool

    func makeCoordinator() -> CloseGuardDelegate {
        CloseGuardDelegate()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view has no window until after this returns, which is why attaching is deferred
        // rather than done here.
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, shouldClose: shouldClose)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // `shouldClose` closes over SwiftUI state, so it is stale the moment that state changes.
        // Re-handing it on every update is what keeps the answer current.
        context.coordinator.attach(to: view.window, shouldClose: shouldClose)
    }

    static func dismantleNSView(_ view: NSView, coordinator: CloseGuardDelegate) {
        coordinator.detach()
    }
}

/// Answers `windowShouldClose(_:)`, and forwards everything else to the delegate that was already
/// there — SwiftUI's own, which a `Window` scene relies on.
private final class CloseGuardDelegate: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private weak var previous: NSWindowDelegate?
    private var shouldClose: (() -> Bool)?

    func attach(to window: NSWindow?, shouldClose: @escaping () -> Bool) {
        self.shouldClose = shouldClose

        guard let window, window !== self.window else { return }
        // A window this object has not seen before: remember whoever was answering for it.
        if window.delegate !== self {
            previous = window.delegate
            window.delegate = self
        }
        self.window = window
    }

    func detach() {
        if let window, window.delegate === self {
            window.delegate = previous
        }
        window = nil
        previous = nil
        shouldClose = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose?() ?? true else { return false }
        // Allowed through here, so let the original delegate have its say too.
        return previous?.windowShouldClose?(sender) ?? true
    }

    // MARK: Forwarding

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previous?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return previous
    }
}
