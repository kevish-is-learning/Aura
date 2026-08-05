//
//  LRCParser.swift
//  sexophone
//
//  Robust LRC synchronized lyrics parser supporting fractional seconds,
//  multiple timestamps per line, global offset tags, and binary search index lookup.
//

import Foundation

/// Pure utility struct for parsing LRC text into timestamped `LyricLine` arrays.
struct LRCParser {

    /// Parses raw LRC string content into an array of `LyricLine` sorted by timestamp.
    static func parse(_ lrcText: String) -> [LyricLine] {
        guard !lrcText.isEmpty else { return [] }

        var lines: [LyricLine] = []
        var globalOffsetSeconds: TimeInterval = 0.0

        let rawLines = lrcText.components(separatedBy: .newlines)

        // Regex for metadata offset tag: [offset: +/- milliseconds]
        let offsetRegex = try? NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\s*\]"#, options: .caseInsensitive)

        // Regex for matching timestamps like [01:23.45] or [01:23.456]
        let timestampRegex = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Check for global offset tag
            if let offsetRegex = offsetRegex {
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                if let match = offsetRegex.firstMatch(in: trimmed, options: [], range: range),
                   let offsetRange = Range(match.range(at: 1), in: trimmed),
                   let offsetMs = Double(trimmed[offsetRange]) {
                    globalOffsetSeconds = offsetMs / 1000.0
                    continue
                }
            }

            // Skip common metadata tags
            if isMetadataTag(trimmed) {
                continue
            }

            // Extract all timestamps on this line
            let nsString = trimmed as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = timestampRegex?.matches(in: trimmed, options: [], range: range) ?? []

            if matches.isEmpty {
                continue
            }

            // Strip out timestamp tags to get remaining text
            var text = timestampRegex?.stringByReplacingMatches(
                in: trimmed,
                options: [],
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespaces) ?? ""

            // Treat instrumental or empty text cleanly
            if text == "♪" || text.lowercased() == "[instrumental]" {
                text = "♪"
            }

            // For each timestamp match, calculate seconds and construct LyricLine
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let minRange = Range(match.range(at: 1), in: trimmed),
                      let secRange = Range(match.range(at: 2), in: trimmed),
                      let minutes = Double(trimmed[minRange]),
                      let seconds = Double(trimmed[secRange]) else {
                    continue
                }

                let totalSeconds = (minutes * 60.0) + seconds + globalOffsetSeconds
                let adjustedSeconds = max(0.0, totalSeconds)

                lines.append(LyricLine(timestamp: adjustedSeconds, text: text))
            }
        }

        // Sort lines chronologically
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    /// Checks if a line is an LRC header/metadata tag (e.g., [ar:Artist], [ti:Title]).
    private static func isMetadataTag(_ line: String) -> Bool {
        let tagPatterns = ["^[ar:", "^[ti:", "^[al:", "^[by:", "^[re:", "^[ve:", "^[length:"]
        let lower = line.lowercased()
        return tagPatterns.contains { lower.hasPrefix($0) }
    }

    /// Binary search to find the active lyric line index for a given playback position.
    /// Returns `-1` if playback is before the first lyric line or if lines array is empty.
    static func currentLyricIndex(for position: TimeInterval, in lines: [LyricLine]) -> Int {
        guard !lines.isEmpty else { return -1 }
        guard position >= lines[0].timestamp else { return -1 }

        var low = 0
        var high = lines.count - 1
        var result = -1

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].timestamp <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result
    }
}
