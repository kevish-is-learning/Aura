//
//  ContentView.swift
//  sexophone
//
//  Apple Music Liquid Glass Floating Player with Synchronized Lyrics
//

import SwiftUI
import SkyLightWindow

// MARK: - 1. Glass Effect Modifier

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                fallbackGlassLayer
            }
            .overlay {
                edgeHighlights
            }
            .shadow(color: .black.opacity(0.26), radius: 24, x: 0, y: 14)
            .shadow(color: .white.opacity(0.10), radius: 3, x: 0, y: -1)
    }

    private var fallbackGlassLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(opacity)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.34), location: 0.0),
                            .init(color: .white.opacity(0.10), location: 0.20),
                            .init(color: .clear, location: 0.55),
                            .init(color: .black.opacity(0.12), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
        }
    }

    private var edgeHighlights: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.86), location: 0.0),
                            .init(color: .white.opacity(0.34), location: 0.22),
                            .init(color: .clear, location: 0.56),
                            .init(color: .white.opacity(0.28), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )

            RoundedRectangle(cornerRadius: max(0, cornerRadius - 1), style: .continuous)
                .strokeBorder(.black.opacity(0.10), lineWidth: 0.6)
                .padding(1)
        }
    }
}

extension View {
    @ViewBuilder
    func applyGlassBackground() -> some View {
        #if os(visionOS)
        if #available(visionOS 1.0, *) {
            self.glassBackgroundEffect()
        } else {
            self
        }
        #else
        self
        #endif
    }

    func liquidGlass(cornerRadius: CGFloat = 24, opacity: Double = 0.76) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
            .applyGlassBackground()
    }
}

// MARK: - 2. Fluid Blending Container (Metaball Morphing)

struct MetaballEffectContainer<Content: View>: View {
    var blurRadius: CGFloat
    @ViewBuilder var content: Content

    init(
        blurRadius: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) {
        self.blurRadius = blurRadius
        self.content = content()
    }

    var body: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            Rectangle()
                .fill(.clear)
                .overlay {
                    Canvas { context, size in
                        context.addFilter(.alphaThreshold(min: 0.5, color: .white))
                        context.addFilter(.blur(radius: blurRadius))

                        if let resolvedContent = context.resolveSymbol(id: 0) {
                            context.draw(resolvedContent, at: CGPoint(x: size.width / 2, y: size.height / 2))
                        }
                    } symbols: {
                        content.tag(0)
                    }
                }
        } else {
            content.blur(radius: blurRadius / 2)
        }
    }
}

// MARK: - 3. Main Player View with Liquid Glass & Synchronized Lyrics

struct ContentView: View {

    // MARK: - Central Playback Manager State
    @StateObject private var manager = PlaybackManager()

    // MARK: - Local UI State
    @State private var isSeeking: Bool = false
    @State private var seekProgress: CGFloat = 0
    @State private var liquidOffset: CGSize = .zero

    // MARK: - Body
    var body: some View {
        HStack(spacing: 16) {
            // Player Card
            playerCardView

            // Synchronized Lyrics Drawer Card (Visible when showLyrics is true)
            if manager.showLyrics {
                LyricsView(manager: manager)
                    .frame(width: 320, height: 286)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.showLyrics)
        .onAppear {
            configureWindow()
            setupLockScreenListeners()
        }
        .moveToSky()
    }

    // MARK: - Player Card Component

    private var playerCardView: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .liquidGlass(cornerRadius: 58, opacity: 0.68)

            VStack(spacing: 14) {
                HStack {
                    sourceAppLabel
                    Spacer()

                    // Lyrics Toggle Button
                    Button {
                        manager.showLyrics.toggle()
                        animateLiquid()
                    } label: {
                        Image(systemName: manager.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(manager.showLyrics ? .white : .white.opacity(0.55))
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(manager.showLyrics ? .white.opacity(0.2) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle Lyrics")
                }

                HStack(alignment: .top, spacing: 18) {
                    artworkView

                    VStack(alignment: .leading, spacing: 5) {
                        Text(manager.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(manager.artist.isEmpty ? manager.album : manager.artist)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)

                        // Current Synced Lyric Snippet Subtitle
                        if let currentLine = manager.currentLyric {
                            Text(currentLine.text)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 16)

                    Spacer(minLength: 18)
                }

                HStack(spacing: 12) {
                    Text(formatTime(displayedElapsed))
                        .frame(width: 44, alignment: .leading)

                    seekSlider

                    Text("-\(formatTime(displayedRemainingTime))")
                        .frame(width: 50, alignment: .trailing)
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

                HStack(alignment: .center) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white.opacity(0.44))

                    Spacer()

                    HStack(spacing: 72) {
                        Button {
                            manager.previousTrack()
                            animateLiquid()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)

                        Button {
                            manager.togglePlayPause()
                            animateLiquid()
                        } label: {
                            Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 43, weight: .bold))
                                .foregroundStyle(.white.opacity(0.96))
                                .frame(width: 52, height: 52)
                                .offset(x: manager.isPlaying ? 0 : 4)
                        }
                        .buttonStyle(.plain)

                        Button {
                            manager.nextTrack()
                            animateLiquid()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white.opacity(0.90))
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Image(systemName: "repeat")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white.opacity(0.44))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 30)

        }
        .frame(width: 620, height: 286)
    }

    private var sourceAppLabel: some View {
        Group {
            if !manager.appName.isEmpty {
                Text(manager.appName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .textCase(.uppercase)
            }
        }
        .frame(height: 16)
    }

    private var artworkView: some View {
        Group {
            if let art = manager.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.92), Color.purple.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.55))
                    }
            }
        }
        .frame(width: 98, height: 98)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
    }

    private var seekSlider: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = displayedProgress
            let filledWidth = width * progress
            let thumbX = min(max(filledWidth, 8), max(width - 8, 8))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: 8)
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                    }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.98), .white.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: filledWidth, height: 8)
                    .shadow(color: .white.opacity(0.46), radius: 5, x: 0, y: 0)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .fill(.white.opacity(0.42))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.86), lineWidth: 0.9)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 5, x: 0, y: 2)
                    .shadow(color: .white.opacity(0.45), radius: 3, x: 0, y: 0)
                    .offset(x: thumbX - 9)
                    .opacity(manager.duration > 0 ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard manager.duration > 0, width > 0 else { return }
                        isSeeking = true
                        seekProgress = normalizedProgress(for: value.location.x, width: width)
                    }
                    .onEnded { value in
                        guard manager.duration > 0, width > 0 else { return }
                        let progress = normalizedProgress(for: value.location.x, width: width)
                        let targetTime = Double(progress) * manager.duration
                        seekProgress = progress
                        manager.seek(to: targetTime)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isSeeking = false
                        }
                    }
            )
        }
        .frame(height: 24)
    }

    private var displayedProgress: CGFloat {
        if isSeeking {
            return seekProgress
        }
        guard manager.duration > 0 else { return 0 }
        return max(0, min(CGFloat(manager.estimatedPlaybackPosition / manager.duration), 1))
    }

    private var displayedElapsed: Double {
        if isSeeking {
            return Double(seekProgress) * manager.duration
        }
        return manager.estimatedPlaybackPosition
    }

    private var displayedRemainingTime: Double {
        max(0, manager.duration - displayedElapsed)
    }

    private func normalizedProgress(for xPosition: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return max(0, min(xPosition / width, 1))
    }

    private func animateLiquid() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            liquidOffset = CGSize(
                width: CGFloat.random(in: -25...25),
                height: CGFloat.random(in: -20...20)
            )
        }
    }

    // MARK: - Native Window Config & Lock Screen Visibility

    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.styleMask.insert(.borderless)
        window.styleMask.remove(.titled)
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.level = .floating

        DispatchQueue.main.async {
            window.setIsVisible(false)
            window.orderOut(nil)
        }
    }

    private func setupLockScreenListeners() {
        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            print("[LockScreen] Screen Locked -> Showing Player")
            if let window = NSApplication.shared.windows.first {
                window.setIsVisible(true)
                window.orderFrontRegardless()
            }
        }

        dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            print("[LockScreen] Screen Unlocked -> Hiding Player")
            if let window = NSApplication.shared.windows.first {
                window.orderOut(nil)
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite && s >= 0 else { return "0:00" }
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

#Preview {
    ContentView()
}
