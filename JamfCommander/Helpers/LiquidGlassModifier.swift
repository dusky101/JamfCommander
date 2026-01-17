//
//  LiquidGlassModifier.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

// The "macOS 26" Liquid Glass Aesthetic
struct LiquidGlassStyle: ViewModifier {
    var type: GlassType
    
    enum GlassType {
        case sidebar    // Darker/frosted, sharp edges on one side
        case content    // Floating, rounded, lighter
        case panel      // Pop-up sheets, thick material
    }
    
    func body(content: Content) -> some View {
        content
            .background(backgroundMaterial)
            .cornerRadius(cornerRadius)
            .shadow(color: shadowColor, radius: 10, x: 0, y: 5)
            .overlay(
                // The "Glass" Stroke Effect
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    // MARK: - Style Logic
    
    var cornerRadius: CGFloat {
        switch type {
        case .sidebar:
            return 0 // Sidebars usually connect flush to the window edge
        case .content:
            return 16 // Floating content looks better rounded
        case .panel:
            return 12
        }
    }
    
    var backgroundMaterial: some ShapeStyle {
        switch type {
        case .sidebar:
            return .ultraThinMaterial // Deep frosted look
        case .content:
            return .regularMaterial   // Standard window feel
        case .panel:
            return .thickMaterial     // Solid pop-up feel
        }
    }
    
    var shadowColor: Color {
        // Sidebars usually don't cast a shadow in split views, but content does
        switch type {
        case .sidebar:
            return Color.clear
        default:
            return Color.black.opacity(0.1)
        }
    }
}

// MARK: - View Extension

extension View {
    // Default to .content if no type is specified
    func liquidGlass(_ type: LiquidGlassStyle.GlassType = .content) -> some View {
        self.modifier(LiquidGlassStyle(type: type))
    }
}
