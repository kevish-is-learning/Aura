//
//  ContentView.swift
//  sexophone
//
//  Apple Music Liquid Glass Floating Player with Metaball Fluid Morphing
//

import SwiftUI
import MediaRemoteAdapter
import SkyLightWindow

// MARK: - 1. Glass Effect Modifier

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: Double
    
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(opacity)
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.35),
                                    .white.opacity(0.08),
                                    .clear,
                                    .white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.6),
                                .white.opacity(0.15),
                                .clear,
                                .white.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 25, x: 0, y: 12)
    }
}

extension View {
    func glassEffect(cornerRadius: CGFloat = 24, opacity: Double = 0.85) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - 2. Fluid Blending Container (Metaball Morphing)

struct GlassEffectContainer<Content: View>: View {
    var blurRadius: CGFloat
    var thresholdCutoff: CGFloat
    @ViewBuilder var content: Content

    init(
        blurRadius: CGFloat = 22,
        thresholdCutoff: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.blurRadius = blurRadius
        self.thresholdCutoff = thresholdCutoff
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

// MARK: - 3. Main Player View with Liquid Glass Effect

struct ContentView: View {

    // MARK: - State
    @State private var title: String = "Nothing Playing"
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var appName: String = ""
    @State private var isPlaying: Bool = false
    @State private var artwork: NSImage? = nil
    @State private var elapsed: Double = 0
    @State private var duration: Double = 0
    @State private var isHovering: Bool = false
    @State private var liquidOffset: CGSize = .zero

    // MediaRemoteAdapter controller
    private let controller = MediaController()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 16) {
            
            // MARK: - Album Artwork & Liquid Metaball Background
            ZStack {
                // Liquid Metaball Glow
                GlassEffectContainer(blurRadius: 18) {
                    ZStack {
                        Circle()
                            .fill(isPlaying ? Color.pink.opacity(0.8) : Color.blue.opacity(0.5))
                            .frame(width: 140, height: 140)
                            .offset(liquidOffset)
                        
                        Circle()
                            .fill(isPlaying ? Color.purple.opacity(0.8) : Color.cyan.opacity(0.5))
                            .frame(width: 100, height: 100)
                            .offset(x: -liquidOffset.width * 0.8, y: -liquidOffset.height * 0.8)
                    }
                    .frame(width: 220, height: 220)
                }
                .blur(radius: 10)
                
                // Artwork
                if let art = artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 10)
                        .scaleEffect(isPlaying ? 1.0 : 0.94)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPlaying)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 200, height: 200)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 48, weight: .thin))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                }
            }
            .frame(width: 220, height: 220)

            // MARK: - Track & Artist Metadata
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                if !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                if !album.isEmpty {
                    Text(album)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)

            // MARK: - Liquid Progress Bar
            if duration > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.15))
                                .frame(height: 5)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.9), .white.opacity(0.6)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geo.size.width * CGFloat(elapsed / duration), geo.size.width)), height: 5)
                                .shadow(color: .white.opacity(0.5), radius: 4, x: 0, y: 0)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text(formatTime(elapsed))
                        Spacer()
                        Text("-\(formatTime(max(0, duration - elapsed)))")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 8)
            }

            // MARK: - Apple Music Playback Controls
            HStack(spacing: 36) {
                Button {
                    controller.previousTrack()
                    animateLiquid()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Button {
                    controller.togglePlayPause()
                    animateLiquid()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 52, height: 52)
                            .glassEffect(cornerRadius: 26, opacity: 0.6)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    controller.nextTrack()
                    animateLiquid()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            // MARK: - Source App Glass Pill
            if !appName.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "wave.3.forward.circle.fill")
                        .font(.system(size: 11))
                    Text(appName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassEffect(cornerRadius: 12, opacity: 0.4)
            }
        }
        .padding(24)
        .frame(width: 280)
        .glassEffect(cornerRadius: 28, opacity: 0.85)
        .onAppear {
            startListening()
            configureWindow()
            setupLockScreenListeners()
        }
        .moveToSky()
    }

    // MARK: - Liquid Morph Animation
    private func animateLiquid() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            liquidOffset = CGSize(
                width: CGFloat.random(in: -25...25),
                height: CGFloat.random(in: -20...20)
            )
        }
    }

    // MARK: - MediaRemoteAdapter Setup

    private func startListening() {
        controller.onTrackInfoReceived = { trackInfo in
            guard let info = trackInfo else {
                title = "Nothing Playing"
                artist = ""
                album = ""
                appName = ""
                isPlaying = false
                artwork = nil
                elapsed = 0
                duration = 0
                return
            }

            let p = info.payload
            title     = p.title           ?? "Unknown"
            artist    = p.artist          ?? ""
            album     = p.album           ?? ""
            appName   = p.applicationName ?? ""
            isPlaying = p.isPlaying      ?? false
            artwork   = p.artwork

            if let d = p.durationMicros  { duration = d / 1_000_000 }
            if let e = p.currentElapsedTime { elapsed = e }
            
            animateLiquid()
        }

        controller.onListenerTerminated = {
            print("[MediaRemote] listener terminated")
        }

        controller.startListening()
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
        
        // Hide window asynchronously on initial launch so AppKit doesn't force it visible
        DispatchQueue.main.async {
            window.setIsVisible(false)
            window.orderOut(nil)
        }
    }

    private func setupLockScreenListeners() {
        let dnc = DistributedNotificationCenter.default()
        
        // Fired when Mac screen is locked
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
        
        // Fired when Mac screen is unlocked
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
