//
//  LyricsService.swift
//  sexophone
//
//  Actor service that fetches lyrics from LRCLIB using exact matching,
//  fallback candidate scoring, and caching.
//

import Foundation

/// Protocol for network sessions to enable unit testing with mock data.
protocol LyricsNetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: LyricsNetworkSession {}

/// Actor responsible for retrieving and parsing lyrics from LRCLIB.
actor LyricsService {
    private let session: LyricsNetworkSession
    private let cache: LyricsCache
    private let baseURL = "https://lrclib.net/api"

    init(session: LyricsNetworkSession = URLSession.shared, cache: LyricsCache = LyricsCache()) {
        self.session = session
        self.cache = cache
    }

    /// Fetches lyrics for the specified track metadata, returning cached results when available.
    func fetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval? = nil
    ) async throws -> LyricsResult {
        guard let key = LyricsLookupKey.normalize(title: title, artist: artist, album: album) else {
            throw LyricsError.invalidMetadata
        }

        // Check cache first
        if let cached = await cache.get(for: key) {
            return cached
        }

        // Check for an in-flight request
        if let existingTask = await cache.inFlightTask(for: key) {
            return try await existingTask.value
        }

        // Create a new task and register it
        let task = Task<LyricsResult, Error> {
            try await self.performFetch(key: key, originalTitle: title, originalArtist: artist, originalAlbum: album, duration: duration)
        }

        await cache.setInFlightTask(task, for: key)

        defer {
            Task {
                await self.cache.removeInFlightTask(for: key)
            }
        }

        do {
            let result = try await task.value
            await cache.set(result, for: key)
            return result
        } catch {
            throw error
        }
    }

    // MARK: - Network Request Implementation

    private func performFetch(
        key: LyricsLookupKey,
        originalTitle: String,
        originalArtist: String,
        originalAlbum: String,
        duration: TimeInterval?
    ) async throws -> LyricsResult {
        // 1. Try Exact Lookup Endpoint first (/api/get)
        if let exactResult = try? await fetchExact(title: originalTitle, artist: originalArtist, album: originalAlbum, duration: duration, key: key) {
            return exactResult
        }

        try Task.checkCancellation()

        // 2. Try Search Endpoint (/api/search) and score candidates
        if let searchResult = try? await fetchSearch(title: originalTitle, artist: originalArtist, album: originalAlbum, duration: duration, key: key) {
            return searchResult
        }

        throw LyricsError.noLyricsFound
    }

    private func fetchExact(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?,
        key: LyricsLookupKey
    ) async throws -> LyricsResult {
        var components = URLComponents(string: "\(baseURL)/get")
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = duration, duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw LyricsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("sexophone/1.0 (macOS Music Player)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsError.invalidResponse(statusCode: 0)
        }

        if httpResponse.statusCode == 404 {
            throw LyricsError.noLyricsFound
        }

        guard httpResponse.statusCode == 200 else {
            throw LyricsError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        guard let trackResponse = try? decoder.decode(LRCLIBTrackResponse.self, from: data) else {
            throw LyricsError.decodingFailed
        }

        return try parseTrackResponse(trackResponse, key: key)
    }

    private func fetchSearch(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval?,
        key: LyricsLookupKey
    ) async throws -> LyricsResult {
        let cleanedTitle = LyricsLookupKey.cleanTitle(title)
        var components = URLComponents(string: "\(baseURL)/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(cleanedTitle) \(artist)".trimmingCharacters(in: .whitespaces))
        ]

        guard let url = components?.url else {
            throw LyricsError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("sexophone/1.0 (macOS Music Player)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LyricsError.noLyricsFound
        }

        let decoder = JSONDecoder()
        guard let candidates = try? decoder.decode([LRCLIBTrackResponse].self, from: data), !candidates.isEmpty else {
            throw LyricsError.noLyricsFound
        }

        // Score candidates and pick best match
        guard let bestCandidate = selectBestCandidate(candidates: candidates, key: key, targetDuration: duration) else {
            throw LyricsError.noLyricsFound
        }

        return try parseTrackResponse(bestCandidate, key: key)
    }

    // MARK: - Candidate Scoring

    /// Selects the best candidate based on normalized title, artist, album, and duration similarity.
    func selectBestCandidate(
        candidates: [LRCLIBTrackResponse],
        key: LyricsLookupKey,
        targetDuration: TimeInterval?
    ) -> LRCLIBTrackResponse? {
        var bestCandidate: LRCLIBTrackResponse?
        var highestScore = 0.0

        for candidate in candidates {
            guard let cTitle = candidate.trackName, let cArtist = candidate.artistName else {
                continue
            }

            let normCTitle = LyricsLookupKey.cleanTitle(cTitle)
            let normCArtist = cArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            var score = 0.0

            // Title scoring
            if normCTitle == key.title {
                score += 50.0
            } else if normCTitle.contains(key.title) || key.title.contains(normCTitle) {
                score += 25.0
            } else {
                continue // Require at least partial title match
            }

            // Artist scoring
            if normCArtist == key.artist {
                score += 40.0
            } else if normCArtist.contains(key.artist) || key.artist.contains(normCArtist) {
                score += 20.0
            } else {
                continue // Require at least partial artist match
            }

            // Album scoring
            if let cAlbum = candidate.albumName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !cAlbum.isEmpty, !key.album.isEmpty {
                if cAlbum == key.album {
                    score += 10.0
                }
            }

            // Duration difference penalty (if duration available)
            if let targetDuration = targetDuration, let cDuration = candidate.duration, targetDuration > 0 {
                let diff = abs(targetDuration - cDuration)
                if diff <= 3.0 {
                    score += 10.0
                } else if diff <= 10.0 {
                    score += 5.0
                } else if diff > 30.0 {
                    score -= 20.0
                }
            }

            // Prefer candidates with synced lyrics
            if let synced = candidate.syncedLyrics, !synced.isEmpty {
                score += 15.0
            }

            if score > highestScore && score >= 60.0 {
                highestScore = score
                bestCandidate = candidate
            }
        }

        return bestCandidate
    }

    private func parseTrackResponse(_ track: LRCLIBTrackResponse, key: LyricsLookupKey) throws -> LyricsResult {
        let syncedString = track.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plainString = track.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let syncedLines = LRCParser.parse(syncedString)
        let isInstrumental = syncedString.lowercased().contains("[instrumental]") || plainString.lowercased().contains("[instrumental]")

        if syncedLines.isEmpty && plainString.isEmpty && !isInstrumental {
            throw LyricsError.noLyricsFound
        }

        return LyricsResult(
            lookupKey: key,
            syncedLyrics: syncedLines,
            plainLyrics: plainString,
            isInstrumental: isInstrumental
        )
    }
}
