//
//  DeviceSymbols.swift
//  JamfCommander
//
//  Created by Marc Oliff on 17/01/2026.
//

import SwiftUI

enum DeviceSymbols {
    
    /// Returns the specific SF Symbol name based on the model string
    static func iconName(for model: String?) -> String {
        // Safe unwrap and lowercase for matching
        guard let modelName = model?.lowercased() else {
            return "desktopcomputer" // Default fallback
        }
        
        // Match logic (Order matters! Check specific types before generic ones)
        if modelName.contains("book") {
            return "macbook"
        }
        if modelName.contains("mini") {
            return "macmini"
        }
        if modelName.contains("studio") {
            return "macstudio"
        }
        if modelName.contains("mac pro") {
            return "macpro.gen3" // The "Cheese Grater" tower icon
        }
        if modelName.contains("imac") {
            return "desktopcomputer"
        }
        if modelName.contains("xserve") {
            return "xserve"
        }
        
        // Default for unknown desktops
        return "desktopcomputer"
    }
}
