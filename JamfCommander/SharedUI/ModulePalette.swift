//
//  ModulePalette.swift
//  JamfCommander
//
//  One colour per module, defined once.
//
//  The rest of the app uses semantic colours, and `design-system.md` says to keep it that way — this
//  file is the deliberate exception, and it is deliberately the *only* one. The system palette cannot
//  express what this needs: eight modules want eight hues spaced far enough apart to be told apart at
//  a glance, at a consistent lightness so none of them shouts louder than the others. `.blue`,
//  `.teal` and `.cyan` sit within about 35° of each other, and `.gray` has no hue at all, which is
//  why Scripts read as disabled next to everything else.
//
//  The wheel, roughly 45° apart:
//
//      rose  350°  Redundant       spring green 155°  Installomator
//      amber  38°  Profiles        cyan         185°  Blueprints
//      lime   78°  Scripts         azure        220°  Computers
//                                  violet       268°  Packages
//                                  magenta      320°  Policies
//
//  Dashboard has no hue on purpose. It is the overview rather than a kind of Jamf object, and giving
//  it one put a third cool colour beside Blueprints and Computers, which is what made that end of the
//  sidebar hard to read.
//
//  These are tuned for the dark appearance the app is locked to. If a light theme is ever added they
//  will need a light variant — at this chroma several of them fail contrast on white.
//
//  Never reach for a raw colour in a view: add it here, and name it for what it is.
//

import SwiftUI

extension Color {

    // MARK: - Module hues

    /// Policies — magenta.
    static let moduleMagenta = Color(red: 1.000, green: 0.341, blue: 0.761)
    /// Profiles — amber.
    static let moduleAmber = Color(red: 1.000, green: 0.682, blue: 0.227)
    /// Scripts — lime. Fills the one empty slot, between amber and spring green.
    static let moduleLime = Color(red: 0.714, green: 0.949, blue: 0.290)
    /// Installomator — spring green.
    static let moduleSpring = Color(red: 0.216, green: 0.890, blue: 0.608)
    /// Blueprints — cyan.
    static let moduleCyan = Color(red: 0.169, green: 0.890, blue: 0.941)
    /// Computers — azure.
    static let moduleAzure = Color(red: 0.302, green: 0.553, blue: 1.000)
    /// Packages — violet.
    static let moduleViolet = Color(red: 0.663, green: 0.420, blue: 1.000)
    /// Redundant — rose. Warm enough to read as "clear this out" without being an error red.
    static let moduleRose = Color(red: 1.000, green: 0.420, blue: 0.506)

    /// Dashboard — no hue. A light neutral, so the overview sits quietly above the modules.
    static let moduleNeutral = Color(red: 0.780, green: 0.796, blue: 0.839)
}
