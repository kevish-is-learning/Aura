//
//  LyricsView.swift
//  sexophone
//
//  SwiftUI view displaying synchronized LRC lyrics with smooth centered auto-scroll,
//  plain lyrics fallback, loading, empty, and accessibility support.
//

import SwiftUI

struct LyricsView: View {
    @ObservedObject var manager: PlaybackManager
    @ObservedObject var settings: LyricsSettings = .shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            // Header bar with Toggle
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Lyrics")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Toggle(isOn: $settings.enableLyrics) {
                    Text(settings.enableLyrics ? "Enabled" : "Disabled")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Divider()
                .background(.white.opacity(0.12))

            // Main Lyrics Content Area
            Group {
                if !settings.enableLyrics {
                    disabledStateView
                } else if manager.isLoadingLyrics {
                    loadingStateView
                } else if manager.isInstrumental {
                    instrumentalStateView
                } else if manager.lyricsError != nil {
                    errorStateView(manager.lyricsError!)
                } else if !manager.syncedLyrics.isEmpty {
                    syncedLyricsScrollView
                } else if !manager.plainLyrics.isEmpty {
                    plainLyricsScrollView
                } else {
                    noLyricsStateView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .liquidGlass(cornerRadius: 24, opacity: 0.85)
    }

    // MARK: - Synchronized Lyrics View

    private var syncedLyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Top padding for centering
                    Spacer(minLength: 40)

                    ForEach(Array(manager.syncedLyrics.enumerated()), id: \.element.id) { index, line in
                        let isCurrent = (index == manager.currentLyricIndex)
                        let isPast = (index < manager.currentLyricIndex)

                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: isCurrent ? 20 : 16, weight: isCurrent ? .bold : .medium, design: .rounded))
                            .foregroundStyle(
                                isCurrent ? Color.white : (isPast ? Color.white.opacity(0.35) : Color.white.opacity(0.65))
                            )
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 20)
                            .scaleEffect(isCurrent ? 1.05 : 1.0)
                            .shadow(color: isCurrent ? .white.opacity(0.4) : .clear, radius: 8, x: 0, y: 0)
                            .id(index)
                            .onTapGesture {
                                manager.seek(to: line.timestamp)
                            }
                            .accessibilityLabel("Lyric line \(index + 1): \(line.text)")
                            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                    }

                    // Bottom padding for centering
                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: manager.currentLyricIndex) { newIndex in
                guard newIndex >= 0 else { return }
                if reduceMotion {
                    proxy.scrollTo(newIndex, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Plain Lyrics Fallback View

    private var plainLyricsScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(manager.plainLyrics)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(20)
        }
    }

    // MARK: - Status States

    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Fetching lyrics...")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var instrumentalStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "guitars.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.6))
            Text("Instrumental Track")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("No lyrics available for this song.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var noLyricsStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.4))
            Text("No Lyrics Available")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var disabledStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.3))
            Text("Lyrics Disabled")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func errorStateView(_ error: LyricsError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.4))
            Text(error.localizedDescription)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }
}
