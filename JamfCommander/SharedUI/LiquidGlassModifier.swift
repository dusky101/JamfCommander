//
//  LiquidGlassModifier.swift
//  JamfCommander
//
//  Created by Marc Oliff on 16/01/2026.
//

import SwiftUI

struct LiquidGlassStyle: ViewModifier {
    var type: GlassType
    
    enum GlassType {
        case sidebar    // Darker/frosted, sharp edges on one side
        case content    // Floating, rounded, lighter
        case panel      // Pop-up sheets, thick material
        case card       // NEW: For list items inside the dashboard
    }
    
    func body(content: Content) -> some View {
        content
            .background(backgroundMaterial)
            .cornerRadius(cornerRadius)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: yOffset)
            .overlay(
                // The "Glass" Stroke Effect
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .white.opacity(0.1)
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
            return 0 // Main content fills the pane
        case .panel:
            return 16
        case .card:
            return 12 // Cards are rounded
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
        case .card:
            return .thickMaterial     // Cards need to be distinct from the background
        }
    }
    
    var shadowColor: Color {
        switch type {
        case .sidebar:
            return Color.clear
        case .card:
            return Color.black.opacity(0.1) // Cards cast a shadow
        default:
            return Color.clear
        }
    }
    
    var shadowRadius: CGFloat {
        switch type {
        case .card: return 4
        default: return 0
        }
    }
    
    var yOffset: CGFloat {
        switch type {
        case .card: return 2
        default: return 0
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
