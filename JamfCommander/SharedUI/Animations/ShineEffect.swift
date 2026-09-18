//
//  ShineEffect.swift
//  JamfCommander
//
//  A specular highlight that travels across a surface once, out and back.
//
//  Two layers, because that is what a reflection actually is: a wide soft bloom with a tight bright
//  core riding inside it. A single flat band reads as a grey panel sliding over the card, which is
//  precisely what the first attempt at this looked like. `.plusLighter` adds light to what is beneath
//  rather than painting over it, so whatever the surface holds brightens as the streak passes instead
//  of being covered by it.
//
//  It runs once per trigger — never on a loop. A highlight repeating in the corner of the eye is
//  noise in a tool somebody has open all day, and Reduce Motion suppresses it entirely.
//

import SwiftUI

extension View {

    /// Sweeps a highlight across this view once, shortly after it appears and again whenever
    /// `trigger` changes.
    ///
    /// - Parameters:
    ///   - isActive: `false` leaves the view alone entirely — for a card that is mid-operation and
    ///     already showing a spinner, say.
    ///   - cornerRadius: The surface's radius, so the sweep is clipped to its shape.
    ///   - tint: Colours the bloom, so the highlight belongs to the surface it crosses rather than
    ///     looking like a generic white wipe. The core stays white whatever this is.
    ///   - delay: How long after appearing the first sweep runs. The default lets a window finish
    ///     drawing itself, so the sweep is seen rather than lost in it.
    ///   - trigger: Changing this runs the sweep again. Pass something that changes on a deliberate
    ///     act — a hover *entry* count, not the hover state itself, which would also fire on exit.
    func shine<Trigger: Equatable>(
        isActive: Bool = true,
        cornerRadius: CGFloat = 12,
        tint: Color = .white,
        delay: Duration = .milliseconds(400),
        trigger: Trigger
    ) -> some View {
        modifier(
            ShineEffect(
                isActive: isActive,
                cornerRadius: cornerRadius,
                tint: tint,
                delay: delay,
                trigger: trigger
            )
        )
    }
}

// MARK: - The effect

struct ShineEffect<Trigger: Equatable>: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    let tint: Color
    let delay: Duration
    let trigger: Trigger

    /// Bumped to run the sweep. `keyframeAnimator` runs its timeline once per change of this.
    @State private var run = 0

    /// A decorative animation is exactly what this setting exists to stop.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var enabled: Bool { isActive && !reduceMotion }

    func body(content: Content) -> some View {
        // `enabled` reads @Environment and must be read here, on the main actor: the content closure
        // below is nonisolated, so it is captured rather than called into.
        content
            .keyframeAnimator(
                initialValue: ShineValues(),
                trigger: run
            ) { [enabled, cornerRadius, tint] view, value in
                view.overlay {
                    Self.layer(value, isActive: enabled, cornerRadius: cornerRadius, tint: tint)
                }
            } keyframes: { _ in
                // Out, a beat at the far edge, and back. One run per trigger — no `repeating`.
                KeyframeTrack(\.travel) {
                    CubicKeyframe(1, duration: 0.85)
                    LinearKeyframe(1, duration: 0.18)
                    CubicKeyframe(-1, duration: 0.85)
                }
                KeyframeTrack(\.intensity) {
                    LinearKeyframe(1, duration: 0.22)
                    LinearKeyframe(1, duration: 1.4)
                    LinearKeyframe(0, duration: 0.26)
                }
                KeyframeTrack(\.tilt) {
                    CubicKeyframe(22, duration: 0.85)
                    CubicKeyframe(22, duration: 0.18)
                    CubicKeyframe(14, duration: 0.85)
                }
            }
            .task {
                try? await Task.sleep(for: delay)
                if enabled { run += 1 }
            }
            .onChange(of: trigger) {
                if enabled { run += 1 }
            }
    }

    /// The three things the sweep animates, on independent tracks.
    private struct ShineValues: Sendable {
        /// −1 parks the streak just off the leading edge, +1 just off the trailing edge.
        var travel: CGFloat = -1
        /// Fades the streak in and out, so it never appears or vanishes mid-surface.
        var intensity: Double = 0
        /// A few degrees of drift through the sweep. Light moving across a surface changes angle
        /// slightly; a rigidly parallel bar is the thing that reads as a graphic, not a reflection.
        var tilt: Double = 14
    }

    /// `nonisolated static` because `keyframeAnimator`'s content closure runs outside the main actor:
    /// it touches no view state, only the values it is handed.
    @ViewBuilder
    nonisolated private static func layer(
        _ value: ShineValues,
        isActive: Bool,
        cornerRadius: CGFloat,
        tint: Color
    ) -> some View {
        if isActive {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                // Tall enough that the tilted band still crosses the full surface at its corners.
                let bandHeight = height * 2.2
                let bloomWidth: CGFloat = 58
                // Travel is measured so ±1 parks the whole band beyond the edge it left from.
                let x = width / 2 + value.travel * (width / 2 + bloomWidth)

                ZStack {
                    // The bloom: broad and heavily blurred.
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: tint.opacity(0.28), location: 0.45),
                                    .init(color: Color.white.opacity(0.30), location: 0.5),
                                    .init(color: tint.opacity(0.28), location: 0.55),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: bloomWidth, height: bandHeight)
                        .blur(radius: 12)

                    // The core: narrow and barely blurred, the bright line that sells it as a glint.
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.7), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 18, height: bandHeight)
                        .blur(radius: 2.5)
                }
                .rotationEffect(.degrees(value.tilt))
                .position(x: x, y: height / 2)
                .opacity(value.intensity)
                .blendMode(.plusLighter)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .allowsHitTesting(false)
            // Decoration only — whatever this crosses already has its own label.
            .accessibilityHidden(true)
        }
    }
}
