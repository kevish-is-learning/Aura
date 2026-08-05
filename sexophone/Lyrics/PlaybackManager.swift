//
//  PlaybackManager.swift
//  sexophone
//
//  Central observable playback manager that processes Spotify/MediaRemote updates,
//  interpolates live playback position, coordinates LyricsService lookups, and drives
//  controlled 250ms lyric synchronization tasks.
//

import Foundation
import SwiftUI
import Combine
import MediaRemoteAdapter

/// Central music manager coordinating playback state, position estimation, lyrics fetching, and synchronization.
@MainActor
final class PlaybackManager: ObservableObject {

    // MARK: - Published Playback State

    @Published private(set) var title: String = "Nothing Playing"
    @Published private(set) var artist: String = ""
    @Published private(set) var album: String = ""
    @Published private(set) var appName: String = ""
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var artwork: NSImage? = nil
    @Published private(set) var reportedElapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Double = 1.0
    @Published private(set) var lastReportTimestamp: Date = Date()

    // MARK: - Published Lyrics State

    @Published private(set) var syncedLyrics: [LyricLine] = []
    @Published private(set) var plainLyrics: String = ""
    @Published private(set) var currentLyricIndex: Int = -1
    @Published private(set) var isLoadingLyrics: Bool = false
    @Published private(set) var lyricsError: LyricsError? = nil
    @Published private(set) var isInstrumental: Bool = false
    @Published var showLyrics: Bool = false {
        didSet {
            handleShowLyricsToggled()
        }
    }

    // MARK: - Dependencies & Private Tasks

    private let lyricsService: LyricsService
    private let settings: LyricsSettings
    private let controller = MediaController()

    private var activeLyricsKey: LyricsLookupKey?
    private var lyricsFetchTask: Task<Void, Never>?
    private var syncLoopTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?

    // MARK: - Computed Properties

    var currentLyric: LyricLine? {
        guard syncedLyrics.indices.contains(currentLyricIndex) else {
            return nil
        }
        return syncedLyrics[currentLyricIndex]
    }

    /// Computes estimated real-time playback position using reported position, wall-clock time elapsed, and playback rate.
    var estimatedPlaybackPosition: TimeInterval {
        guard duration > 0 else { return 0 }

        if !isPlaying || playbackRate <= 0 {
            return min(max(0, reportedElapsedTime), duration)
        }

        let elapsedWallClock = Date().timeIntervalSince(lastReportTimestamp)
        let estimated = reportedElapsedTime + (elapsedWallClock * playbackRate)

        return min(max(0, estimated), duration)
    }

    // MARK: - Initialization & Cleanup

    init(
        lyricsService: LyricsService = LyricsService(),
        settings: LyricsSettings? = nil
    ) {
        self.lyricsService = lyricsService
        self.settings = settings ?? LyricsSettings.shared

        setupSettingsObserver()
        setupMediaRemoteAdapter()
    }

    deinit {
        lyricsFetchTask?.cancel()
        syncLoopTask?.cancel()
    }

    // MARK: - MediaRemote Update Integration

    private func setupMediaRemoteAdapter() {
        controller.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in
                self?.handleTrackInfoReceived(trackInfo)
            }
        }

        controller.startListening()
    }

    /// Process incoming Spotify / MediaRemote track updates.
    func handleTrackInfoReceived(_ trackInfo: TrackInfo?) {
        guard let info = trackInfo else {
            resetPlaybackAndLyrics()
            return
        }

        let p = info.payload
        let newTitle = p.title ?? "Unknown"
        let newArtist = p.artist ?? ""
        let newAlbum = p.album ?? ""
        let newAppName = p.applicationName ?? ""
        let newIsPlaying = p.isPlaying ?? false
        let newArtwork = p.artwork
        let newDuration = (p.durationMicros ?? 0) / 1_000_000.0
        let newElapsed = p.currentElapsedTime ?? 0
        let newRate = p.playbackRate ?? (newIsPlaying ? 1.0 : 0.0)

        let trackChanged = (title != newTitle || artist != newArtist || album != newAlbum)

        // Update authoritative playback properties
        self.title = newTitle
        self.artist = newArtist
        self.album = newAlbum
        self.appName = newAppName
        self.isPlaying = newIsPlaying
        self.artwork = newArtwork
        self.duration = newDuration
        self.reportedElapsedTime = newElapsed
        self.playbackRate = newRate
        self.lastReportTimestamp = Date()

        // Handle lyrics task update on track change
        if trackChanged {
            handleTrackChanged()
        } else {
            // Check position change for current lyric index
            updateCurrentLyricFromPosition()
        }

        // Control sync loop based on playing state
        manageSyncLoopState()
    }

    /// Seeks to a specific playback position in seconds.
    func seek(to seconds: TimeInterval) {
        let targetTime = min(max(0, seconds), duration)
        reportedElapsedTime = targetTime
        lastReportTimestamp = Date()
        controller.setTime(seconds: targetTime)
        updateCurrentLyricFromPosition()
    }

    func togglePlayPause() {
        controller.togglePlayPause()
    }

    func nextTrack() {
        controller.nextTrack()
    }

    func previousTrack() {
        controller.previousTrack()
    }

    // MARK: - Track Change & Lyrics Fetch Pipeline

    private func handleTrackChanged() {
        lyricsFetchTask?.cancel()

        guard settings.enableLyrics else {
            clearLyricsState()
            return
        }

        guard let newKey = LyricsLookupKey.normalize(title: title, artist: artist, album: album) else {
            activeLyricsKey = nil
            clearLyricsState()
            lyricsError = .invalidMetadata
            return
        }

        if activeLyricsKey == newKey {
            return
        }

        activeLyricsKey = newKey
        currentLyricIndex = -1
        isLoadingLyrics = true
        lyricsError = nil

        let currentDuration = duration

        lyricsFetchTask = Task { [weak self, lyricsService] in
            do {
                let result = try await lyricsService.fetchLyrics(
                    title: newKey.title,
                    artist: newKey.artist,
                    album: newKey.album,
                    duration: currentDuration
                )

                guard !Task.isCancelled else { return }

                await Task { @MainActor [weak self] in
                    self?.applyLyricsResult(result, for: newKey)
                }.value
            } catch {
                guard !Task.isCancelled else { return }

                let errToApply: LyricsError = (error as? LyricsError) ?? .noLyricsFound
                await Task { @MainActor [weak self] in
                    self?.applyLyricsError(errToApply, for: newKey)
                }.value
            }
        }
    }

    private func applyLyricsResult(_ result: LyricsResult, for key: LyricsLookupKey) {
        guard activeLyricsKey == key else { return }

        self.syncedLyrics = result.syncedLyrics
        self.plainLyrics = result.plainLyrics
        self.isInstrumental = result.isInstrumental
        self.isLoadingLyrics = false
        self.lyricsError = nil

        updateCurrentLyricFromPosition()
        manageSyncLoopState()
    }

    private func applyLyricsError(_ error: LyricsError, for key: LyricsLookupKey) {
        guard activeLyricsKey == key else { return }

        self.syncedLyrics = []
        self.plainLyrics = ""
        self.isInstrumental = false
        self.isLoadingLyrics = false
        self.lyricsError = error
        self.currentLyricIndex = -1

        manageSyncLoopState()
    }

    private func resetPlaybackAndLyrics() {
        title = "Nothing Playing"
        artist = ""
        album = ""
        appName = ""
        isPlaying = false
        artwork = nil
        reportedElapsedTime = 0
        duration = 0
        playbackRate = 1.0

        lyricsFetchTask?.cancel()
        activeLyricsKey = nil
        clearLyricsState()
        manageSyncLoopState()
    }

    private func clearLyricsState() {
        syncedLyrics = []
        plainLyrics = ""
        currentLyricIndex = -1
        isLoadingLyrics = false
        lyricsError = nil
        isInstrumental = false
    }

    // MARK: - Synchronization Task Loop

    private func handleShowLyricsToggled() {
        if showLyrics && (syncedLyrics.isEmpty && plainLyrics.isEmpty && lyricsError == nil) {
            handleTrackChanged()
        }
        manageSyncLoopState()
    }

    private func setupSettingsObserver() {
        settingsCancellable = settings.$enableLyrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.handleTrackChanged()
                } else {
                    self?.lyricsFetchTask?.cancel()
                    self?.clearLyricsState()
                    self?.manageSyncLoopState()
                }
            }
    }

    private func manageSyncLoopState() {
        let shouldSync = isPlaying && !syncedLyrics.isEmpty

        if shouldSync {
            startSyncLoopIfNeeded()
        } else {
            stopSyncLoop()
        }
    }

    private func startSyncLoopIfNeeded() {
        guard syncLoopTask == nil else { return }

        syncLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))

                guard !Task.isCancelled else { break }

                await Task { @MainActor [weak self] in
                    self?.updateCurrentLyricFromPosition()
                }.value
            }
        }
    }

    private func stopSyncLoop() {
        syncLoopTask?.cancel()
        syncLoopTask = nil
    }

    /// Evaluates current effective position using binary search and updates `currentLyricIndex` if changed.
    private func updateCurrentLyricFromPosition() {
        guard !syncedLyrics.isEmpty else {
            if currentLyricIndex != -1 {
                currentLyricIndex = -1
            }
            return
        }

        let position = estimatedPlaybackPosition
        let newIndex = LRCParser.currentLyricIndex(for: position, in: syncedLyrics)

        if currentLyricIndex != newIndex {
            currentLyricIndex = newIndex
        }
    }
}
