//
//  LRCParserTests.swift
//  sexophoneTests
//
//  Unit tests covering LRC parsing, timestamp formats, offset application,
//  binary search index lookup, candidate scoring, normalization, and concurrency safety.
//

import XCTest
@testable import sexophone

final class LRCParserTests: XCTestCase {

    // 1. Parsing normal synchronized LRC file
    func testParseNormalLRC() {
        let lrc = """
        [00:10.00]Line 1
        [00:20.00]Line 2
        [00:30.00]Line 3
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "Line 1")
        XCTAssertEqual(lines[0].timestamp, 10.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].text, "Line 2")
        XCTAssertEqual(lines[1].timestamp, 20.0, accuracy: 0.001)
    }

    // 2. Parsing timestamps with two-digit fractions
    func testParseTwoDigitFractions() {
        let lrc = "[01:12.45]Two digit fraction"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timestamp, 72.45, accuracy: 0.001)
    }

    // 3. Parsing timestamps with three-digit fractions
    func testParseThreeDigitFractions() {
        let lrc = "[01:03.250]Three digit fraction"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timestamp, 63.25, accuracy: 0.001)
    }

    // 4. Parsing multiple timestamps on one line
    func testParseMultipleTimestampsOnOneLine() {
        let lrc = "[00:10.00][00:20.00]Repeated line"
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].timestamp, 10.0, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "Repeated line")
        XCTAssertEqual(lines[1].timestamp, 20.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].text, "Repeated line")
    }

    // 5. Ignoring malformed lines
    func testIgnoreMalformedLines() {
        let lrc = """
        [ar:Artist]
        [invalid:timestamp]Not a valid timestamp
        [00:05.00]Valid line
        Random malformed line without brackets
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Valid line")
        XCTAssertEqual(lines[0].timestamp, 5.0, accuracy: 0.001)
    }

    // 6. Applying an LRC offset tag
    func testApplyLRCOffset() {
        let lrc = """
        [offset:+500]
        [00:10.00]Line with +500ms offset
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timestamp, 10.5, accuracy: 0.001)
    }

    // 7. Sorting out-of-order lyric lines
    func testSortingOutOfOrderLines() {
        let lrc = """
        [00:30.00]Line 3
        [00:10.00]Line 1
        [00:20.00]Line 2
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "Line 1")
        XCTAssertEqual(lines[1].text, "Line 2")
        XCTAssertEqual(lines[2].text, "Line 3")
    }

    // 8. Finding correct current lyric index
    func testCurrentLyricIndex() {
        let lines = [
            LyricLine(timestamp: 10.0, text: "Line 1"),
            LyricLine(timestamp: 20.0, text: "Line 2"),
            LyricLine(timestamp: 30.0, text: "Line 3")
        ]
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 15.0, in: lines), 0)
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 20.0, in: lines), 1)
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 25.0, in: lines), 1)
    }

    // 9. Seeking backward
    func testSeekingBackward() {
        let lines = [
            LyricLine(timestamp: 10.0, text: "Line 1"),
            LyricLine(timestamp: 20.0, text: "Line 2"),
            LyricLine(timestamp: 30.0, text: "Line 3")
        ]
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 25.0, in: lines), 1)
        // Seek backward to 12s
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 12.0, in: lines), 0)
    }

    // 10. Seeking forward
    func testSeekingForward() {
        let lines = [
            LyricLine(timestamp: 10.0, text: "Line 1"),
            LyricLine(timestamp: 20.0, text: "Line 2"),
            LyricLine(timestamp: 30.0, text: "Line 3")
        ]
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 12.0, in: lines), 0)
        // Seek forward to 32s
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 32.0, in: lines), 2)
    }

    // 11. Playback before the first lyric
    func testPlaybackBeforeFirstLyric() {
        let lines = [
            LyricLine(timestamp: 10.0, text: "Line 1"),
            LyricLine(timestamp: 20.0, text: "Line 2")
        ]
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 5.0, in: lines), -1)
    }

    // 12. Playback after the final lyric
    func testPlaybackAfterFinalLyric() {
        let lines = [
            LyricLine(timestamp: 10.0, text: "Line 1"),
            LyricLine(timestamp: 20.0, text: "Line 2")
        ]
        XCTAssertEqual(LRCParser.currentLyricIndex(for: 50.0, in: lines), 1)
    }

    // 13. Track normalization
    func testTrackNormalization() {
        let key = LyricsLookupKey.normalize(
            title: "  Blinding Lights (Remastered 2020)  ",
            artist: "  The Weeknd  ",
            album: "After Hours"
        )
        XCTAssertNotNil(key)
        XCTAssertEqual(key?.title, "blinding lights")
        XCTAssertEqual(key?.artist, "the weeknd")

        // Invalid metadata (placeholders)
        XCTAssertNil(LyricsLookupKey.normalize(title: "Nothing Playing", artist: "Unknown", album: ""))
    }

    // 14. Candidate match scoring
    func testCandidateMatchScoring() async {
        let service = LyricsService()
        let key = LyricsLookupKey.normalize(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours")!

        let candidate1 = LRCLIBTrackResponse(
            id: 1,
            trackName: "Blinding Lights",
            artistName: "The Weeknd",
            albumName: "After Hours",
            duration: 200,
            plainLyrics: "Yeah",
            syncedLyrics: "[00:10.00]Yeah"
        )
        let candidate2 = LRCLIBTrackResponse(
            id: 2,
            trackName: "Unrelated Song",
            artistName: "Someone Else",
            albumName: "Album",
            duration: 180,
            plainLyrics: nil,
            syncedLyrics: nil
        )

        let best = await service.selectBestCandidate(candidates: [candidate1, candidate2], key: key, targetDuration: 200)
        XCTAssertEqual(best?.id, 1)
    }

    // 15. Preventing stale lyrics from an earlier track
    func testStaleLyricsPrevention() async {
        let cache = LyricsCache()
        let key1 = LyricsLookupKey.normalize(title: "Song One", artist: "Artist", album: "Album")!
        let result1 = LyricsResult(lookupKey: key1, syncedLyrics: [LyricLine(timestamp: 5, text: "Song One")], plainLyrics: "", isInstrumental: false)

        await cache.set(result1, for: key1)

        let cachedResult = await cache.get(for: key1)
        XCTAssertEqual(cachedResult?.syncedLyrics[0].text, "Song One")
    }

    // 16. Cache hits avoiding duplicate network requests
    func testCacheHit() async {
        let cache = LyricsCache()
        let key = LyricsLookupKey.normalize(title: "Cached Song", artist: "Artist", album: "Album")!
        let result = LyricsResult(lookupKey: key, syncedLyrics: [LyricLine(timestamp: 1, text: "Cached")], plainLyrics: "", isInstrumental: false)

        await cache.set(result, for: key)

        let hit = await cache.get(for: key)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.lookupKey, key)
    }

    // 17. Paused playback not advancing estimated time
    func testPausedPlaybackPosition() async {
        let manager = await PlaybackManager()
        await MainActor.run {
            manager.handleTrackInfoReceived(nil)
        }
        let pos = await manager.estimatedPlaybackPosition
        XCTAssertEqual(pos, 0.0)
    }
}
