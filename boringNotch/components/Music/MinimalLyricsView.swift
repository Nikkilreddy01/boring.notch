//
//  MinimalLyricsView.swift
//  boringNotch
//
//  Created by opencode on 2026-09-17.
//

import AppKit
import Defaults
import SwiftUI

struct MinimalLyricsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared

    @State private var pauseInactivityTask: Task<Void, Never>?
    @State private var isTimedOut: Bool = false
    @State private var hasExpandedOpen: Bool = false

    private let fixedOverlayWidth: CGFloat = 390

    private var hasPhysicalNotch: Bool {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return (screen?.safeAreaInsets.top ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Reserve space for the physical camera notch hardware cutout on MacBook displays
            if hasPhysicalNotch && vm.effectiveClosedNotchHeight > 0 {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
            }

            if !isTimedOut {
                // Continuous Liquid Glass Surface
                HStack(spacing: 12) {
                    // LEFT: Album Artwork (Circular with subtle border and shadow)
                    albumArtView

                    // CENTER: Lyrics Viewport (Current + Next, vertical flow transition, 2-line max)
                    lyricViewportView
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // RIGHT: Existing Music Indicator with Adaptive Artwork Accent
                    rightIndicatorView
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(width: fixedOverlayWidth)
                .background(liquidGlassBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(liquidGlassBorder)
                .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 5)
                .opacity(hasExpandedOpen ? 1 : 0)
                .scaleEffect(hasExpandedOpen ? 1 : 0.94, anchor: .top)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
                ))
            }
        }
        .frame(width: fixedOverlayWidth)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                hasExpandedOpen = true
            }
            handlePlaybackChange(isPlaying: musicManager.isPlaying)
        }
        .onChange(of: musicManager.isPlaying) { _, isPlaying in
            handlePlaybackChange(isPlaying: isPlaying)
        }
    }

    // MARK: - Playback Inactivity (12-second Timeout)
    private func handlePlaybackChange(isPlaying: Bool) {
        pauseInactivityTask?.cancel()
        pauseInactivityTask = nil

        if isPlaying {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                isTimedOut = false
                hasExpandedOpen = true
            }
        } else {
            // Start 12-second playback-inactivity timer when paused
            pauseInactivityTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                    isTimedOut = true
                }
            }
        }
    }

    // MARK: - Liquid Glass Styling
    private var liquidGlassBackground: some View {
        ZStack {
            // Native macOS background blur
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)

            // Subtle dark glass tint for contrast across any wallpaper
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.32))

            // Subtle adaptive artwork glow in glass
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: musicManager.avgColor).opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var liquidGlassBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }

    // MARK: - Album Artwork
    private var albumArtView: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1.5)
    }

    // MARK: - Right Indicator (Adaptive Artwork Accent)
    private var rightIndicatorView: some View {
        Rectangle()
            .fill(
                Defaults[.coloredSpectrogram]
                    ? Color(nsColor: musicManager.avgColor).gradient
                    : Color.white.opacity(0.85).gradient
            )
            .frame(width: 16, height: 14)
            .mask {
                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                    .frame(width: 16, height: 14)
            }
    }

    // MARK: - Lyric Viewport
    @ViewBuilder
    private var lyricViewportView: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let currentElapsed: Double = {
                guard musicManager.isPlaying else { return musicManager.elapsedTime }
                let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                return min(max(progressed, 0), musicManager.songDuration)
            }()

            let lyricData = musicManager.currentAndNextLyric(at: currentElapsed)
            let current = lyricData.current.trimmingCharacters(in: .whitespacesAndNewlines)
            let next = lyricData.next.trimmingCharacters(in: .whitespacesAndNewlines)
            let lyricIndex = lyricData.index

            let displayCurrent: String = {
                if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                if !current.isEmpty { return current }
                if !musicManager.songTitle.isEmpty {
                    return musicManager.songTitle + (musicManager.artistName.isEmpty ? "" : " • " + musicManager.artistName)
                }
                return "♪ Playing"
            }()

            let isPersian = displayCurrent.unicodeScalars.contains { scalar in
                let v = scalar.value
                return v >= 0x0600 && v <= 0x06FF
            }

            VStack(alignment: .leading, spacing: 2) {
                // CURRENT LYRIC: Larger, brighter, primary focus, up to 2 lines
                Text(displayCurrent)
                    .font(
                        isPersian
                            ? .custom("Vazirmatn-Regular", size: 13)
                            : .system(size: 13, weight: .semibold, design: .rounded)
                    )
                    .foregroundColor(musicManager.isFetchingLyrics ? .white.opacity(0.6) : .white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 12).combined(with: .opacity),
                            removal: .offset(y: -12).combined(with: .opacity)
                        )
                    )
                    .id("current_\(lyricIndex)_\(displayCurrent)")

                // NEXT LYRIC: Smaller, subtle, underneath preview
                if !next.isEmpty {
                    Text(next)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .transition(
                            .asymmetric(
                                insertion: .offset(y: 10).combined(with: .opacity),
                                removal: .offset(y: -10).combined(with: .opacity)
                            )
                        )
                        .id("next_\(lyricIndex)_\(next)")
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: lyricIndex)
            .clipped()
        }
    }
}
