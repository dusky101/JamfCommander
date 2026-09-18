//
//  ModuleTransition.swift
//  JamfCommander
//
//  How the detail pane changes when you change module.
//
//  The sidebar is an ordered list, so movement through it has a direction, and the pane says which
//  way you went: pick something further down and the new module arrives from the right while the old
//  one leaves to the left; pick something further up and both reverse. Two clicks down and one back
//  up retrace the same path, so the modules feel like places in a fixed order rather than a set of
//  screens that each appear from nowhere.
//
//  Horizontal on purpose. Every module's content scrolls vertically, and a pane that slid vertically
//  would read as a scroll for the first fraction of a second before turning out not to be — worse
//  than no transition at all. Sliding across the scroll axis can never be mistaken for one, and it
//  matches the forward/back motion people already know from paged interfaces.
//
//  Only the pane moves. The sidebar is the fixed thing you navigate *from*; animating it as well
//  would leave nothing on screen holding still.
//

import SwiftUI

/// Which way through the sidebar's order the pane is travelling.
enum ModuleTransitionDirection {
    /// Towards the end of the list.
    case forward
    /// Towards the start of the list.
    case backward

    /// The edge a new pane enters from.
    var entryEdge: Edge { self == .forward ? .trailing : .leading }

    /// The edge the outgoing pane leaves by — always the opposite, so the pair reads as one movement
    /// rather than two unrelated ones.
    var exitEdge: Edge { self == .forward ? .leading : .trailing }
}

extension AnyTransition {

    /// The detail pane's arrival and departure for one change of module.
    ///
    /// A full slide rather than a nudge: the incoming module is very often a loading spinner on the
    /// same background as the one it replaced, and a short offset plus a fade is invisible against
    /// that. Travelling the pane's whole width is the version you can actually see.
    static func modulePane(_ direction: ModuleTransitionDirection) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction.entryEdge).combined(with: .opacity),
            removal: .move(edge: direction.exitEdge).combined(with: .opacity)
        )
    }
}

extension AppModule {

    /// Where this module sits in the sidebar, counting the pinned Redundant entry last.
    ///
    /// `allCases` is declared in sidebar order, so this reads the order somebody actually sees rather
    /// than a second list that could drift out of step with it.
    var navigationIndex: Int {
        AppModule.allCases.firstIndex(of: self) ?? 0
    }
}
