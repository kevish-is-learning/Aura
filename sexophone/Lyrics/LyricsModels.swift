//
//  LyricsModels.swift
//  sexophone
//
//  Models for synchronized and plain lyrics, lookup keys, and errors.
//

import Foundation

// MARK: - Lyric Line Model

/// Represents a single timed lyric line in a synchronized song.
struct LyricLine: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let text: String

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

// MARK: - Lyrics Lookup Key

/// Normalized cache and query key for matching track lyrics.
struct LyricsLookupKey: Hashable, Sendable {
    let title: String
    let artist: String
    let album: String

    /// Returns a normalized lookup key with lowercase, trimmed strings and stripped remastered suffixes.
    static func normalize(title: String, artist: String, album: String) -> LyricsLookupKey? {
        let cleanedTitle = cleanTitle(title)
        let cleanedArtist = cleanMetadata(artist)
        let cleanedAlbum = cleanMetadata(album)

        guard isValidMetadata(title: cleanedTitle, artist: cleanedArtist) else {
            return nil
        }

        return LyricsLookupKey(
            title: cleanedTitle,
            artist: cleanedArtist,
            album: cleanedAlbum
        )
    }

    /// Checks if title and artist represent valid track metadata rather than empty or placeholder strings.
    private static func isValidMetadata(title: String, artist: String) -> Bool {
        guard !title.isEmpty, !artist.isEmpty else { return false }
        let invalidPlaceholders: Set<String> = [
            "unknown", "unknown artist", "not playing", "nothing playing", "empty", "n/a", "none"
        ]
        if invalidPlaceholders.contains(title.lowercased()) || invalidPlaceholders.contains(artist.lowercased()) {
            return false
        }
        return true
    }

    private static func cleanMetadata(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Removes common suffixes such as (Remastered 2020), - Live, (Deluxe Edition), etc.
    static func cleanTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove parenthesized or bracketed suffixes
        let patterns = [
            #"\s*[\(\[\{].*?(remaster|live|deluxe|edition|version|radio edit|acoustic|mono|stereo|\d{4}).*?[\)\]\}]"#,
            #"\s*-\s*.*?(remaster|live|deluxe|edition|version|radio edit|acoustic|mono|stereo|\d{4}).*$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - LRCLIB Response Models

/// DTO for LRCLIB API responses.
struct LRCLIBTrackResponse: Codable, Sendable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
}

// MARK: - Lyrics Result

/// Final resolved lyrics payload.
struct LyricsResult: Equatable, Sendable {
    let lookupKey: LyricsLookupKey
    let syncedLyrics: [LyricLine]
    let plainLyrics: String
    let isInstrumental: Bool

    var hasSyncedLyrics: Bool {
        !syncedLyrics.isEmpty
    }

    var hasAnyLyrics: Bool {
        !syncedLyrics.isEmpty || !plainLyrics.isEmpty
    }
}

// MARK: - Lyrics Error

/// Typed errors for lyrics fetch and parsing failures.
enum LyricsError: Error, Equatable, Sendable, LocalizedError {
    case invalidMetadata
    case invalidURL
    case requestFailed
    case invalidResponse(statusCode: Int)
    case decodingFailed
    case noLyricsFound
    case taskCancelled

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "No valid track metadata to search lyrics."
        case .invalidURL:
            return "Failed to construct LRCLIB request URL."
        case .requestFailed:
            return "Network connection failed."
        case .invalidResponse(let statusCode):
            return "Server responded with error status (\(statusCode))."
        case .decodingFailed:
            return "Failed to process lyrics format."
        case .noLyricsFound:
            return "No lyrics found for this track."
        case .taskCancelled:
            return "Request was cancelled."
        }
    }
}
