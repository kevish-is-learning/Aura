//
//  sexophoneApp.swift
//  sexophone
//
//  Created by Kevish Sewliya on 04/08/26.
//

import SwiftUI

@main
struct sexophoneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Hide the title bar initially so it doesn't flash before our borderless config
        .windowStyle(.hiddenTitleBar)
    }
}
