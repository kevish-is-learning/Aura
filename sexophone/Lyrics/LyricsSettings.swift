//
//  LyricsSettings.swift
//  sexophone
//
//  Centralized user preferences for lyrics enabling/disabling.
//

import Foundation
import Combine

/// Centralized manager for lyrics settings backed by `UserDefaults`.
@MainActor
final class LyricsSettings: ObservableObject {

    static let shared = LyricsSettings()

    private static let enableLyricsKey = "enableLyrics"

    @Published var enableLyrics: Bool {
        didSet {
            UserDefaults.standard.set(enableLyrics, forKey: Self.enableLyricsKey)
        }
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.enableLyricsKey) == nil {
            self.enableLyrics = true
        } else {
            self.enableLyrics = UserDefaults.standard.bool(forKey: Self.enableLyricsKey)
        }
    }
}
