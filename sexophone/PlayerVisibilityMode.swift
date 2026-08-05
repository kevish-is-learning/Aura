//
//  PlayerVisibilityMode.swift
//  sexophone
//
//  Display mode setting: Lock Screen Only vs Always on All Screens.
//

import SwiftUI

enum PlayerVisibilityMode: String, CaseIterable, Identifiable {
    case lockScreenOnly = "lockScreenOnly"
    case alwaysOnScreen = "alwaysOnScreen"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreenOnly:
            return "Lock Screen Only"
        case .alwaysOnScreen:
            return "Always on All Screens"
        }
    }

    var iconName: String {
        switch self {
        case .lockScreenOnly:
            return "lock.display"
        case .alwaysOnScreen:
            return "display.on.fly"
        }
    }

    var description: String {
        switch self {
        case .lockScreenOnly:
            return "Player appears only when the Mac is locked"
        case .alwaysOnScreen:
            return "Player stays visible floating across all screens"
        }
    }
}
