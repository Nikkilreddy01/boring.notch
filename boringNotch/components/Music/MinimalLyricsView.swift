//
//  MinimalLyricsView.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-17.
//

import Defaults
import SwiftUI

struct MinimalLyricsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel

    @State private var isExpanded: Bool = false
    @State private var isTimedOut: Bool = false
    @State private var pauseInactivityTask: Task<Void, Never>?

    private let targetWidth: CGFloat = 390

    private var hasPhysicalNotch: Bool {
        guard let currentScreen = vm.screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return false
        }
        return (currentScreen.safeAreaInsets.top) > 0
    }

    private var notchHeight: CGFloat {
        hasPhysicalNotch ? vm.effectiveClosedNotchHeight : 0
    }

    var body: some View {
        let (current, next, lyricIndex) = musicManager.currentAndNextLyric(at: musicManager.elapsedTime)

        let resolvedCurrent: String = {
            if !current.isEmpty {
                return current
            }
            if musicManager.isFetchingLyrics {
                return "Fetching lyrics…"
            }
            return musicManager.songTitle
        }()

        let resolvedNext: String = {
            if !next.isEmpty {
                return next
            }
            if current.isEmpty && !musicManager.isFetchingLyrics {
                return musicManager.artistName
            }
            return ""
        }()

        let displayCurrent = resolvedCurrent.isEmpty ? musicManager.songTitle : resolvedCurrent
        let isLongCurrent = displayCurrent.count > 34
        let barHeight: CGFloat = isLongCurrent ? 52 : 46
        let cornerRadius: CGFloat = isLongCurrent ? 20 : 23

        VStack(alignment: .center, spacing: 0) {
            // 1. Untouched Physical Camera Notch Area (Standard Black Mask)
            if notchHeight > 0 {
                NotchShape(
                    topCornerRadius: cornerRadiusInsets.closed.top,
                    bottomCornerRadius: cornerRadiusInsets.closed.bottom
                )
                .fill(Color.black)
                .frame(width: vm.closedNotchSize.width, height: notchHeight)
            }

            // 2. Clear Gap Between Physical Notch and Floating Bar
            Color.clear
                .frame(width: targetWidth, height: (notchHeight > 0 ? 8 : 12))

            // 3. Separate Floating Liquid Glass Bar Below the Notch
            if isExpanded && !isTimedOut {
                HStack(spacing: 12) {
                    // LEFT: Album Artwork (Circular with subtle border & shadow)
                    albumArtView

                    // CENTER: Current + Next Lyrics (Vertical Flow Transition)
                    lyricContentView(displayCurrent: displayCurrent, next: resolvedNext, lyricIndex: lyricIndex, isLongCurrent: isLongCurrent)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // RIGHT: Existing Music Indicator with Adaptive Artwork Accent
                    rightIndicatorView
                }
                .padding(.horizontal, 14)
                .frame(width: targetWidth, height: barHeight)
                .background(
                    liquidGlassBackground(cornerRadius: cornerRadius)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 7)
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.94, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
                    )
                )
            }
        }
        .frame(width: targetWidth, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isExpanded)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isTimedOut)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: barHeight)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                isExpanded = true
            }
            handlePlaybackChange(isPlaying: musicManager.isPlaying)
        }
        .onChange(of: musicManager.isPlaying) { _, isPlaying in
            handlePlaybackChange(isPlaying: isPlaying)
        }
    }

    // MARK: - Native macOS Liquid Glass Background (Matching Control Center)
    @ViewBuilder
    private func liquidGlassBackground(cornerRadius: CGFloat) -> some View {
        ZStack {
            // 1. Native macOS Blur Material
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            // 2. Dark Translucent Substrate (Deep contrast, native macOS feel)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.36))

            // 3. Top Specular Reflection Highlight
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.14), location: 0.0),
                            .init(color: Color.white.opacity(0.02), location: 0.35),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            // 4. Specular Hairline Perimeter Stroke
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.40), location: 0.0),
                            .init(color: Color.white.opacity(0.16), location: 0.3),
                            .init(color: Color.white.opacity(0.04), location: 0.7),
                            .init(color: Color.white.opacity(0.12), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
    }

    // MARK: - Playback Inactivity (12s Timeout)
    private func handlePlaybackChange(isPlaying: Bool) {
        pauseInactivityTask?.cancel()
        pauseInactivityTask = nil

        if isPlaying {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                isTimedOut = false
                isExpanded = true
            }
        } else {
            // 12-second playback-inactivity timer when paused
            pauseInactivityTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.90)) {
                    isExpanded = false
                }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                isTimedOut = true
            }
        }
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
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1.5)
    }

    // MARK: - Right Indicator (Adaptive Artwork Accent)
    private var rightIndicatorView: some View {
        Rectangle()
            .fill(
                Defaults[.coloredSpectrogram]
                    ? Color(nsColor: musicManager.avgColor).gradient
                    : Color.white.opacity(0.9).gradient
            )
            .frame(width: 16, height: 14)
            .mask {
                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                    .frame(width: 16, height: 14)
            }
    }

    // MARK: - Lyric Content View (Current + Next, Vertical Flow Transition)
    @ViewBuilder
    private func lyricContentView(displayCurrent: String, next: String, lyricIndex: Int, isLongCurrent: Bool) -> some View {
        let isPersian = displayCurrent.unicodeScalars.contains { scalar in
            let v = scalar.value
            return v >= 0x0600 && v <= 0x06FF
        }

        VStack(alignment: .leading, spacing: 2) {
            // CURRENT LYRIC: Larger, brighter, primary focus, up to 2 lines
            Text(displayCurrent)
                .font(
                    isPersian
                        ? .custom("Vazirmatn-Regular", size: 12.5)
                        : .system(size: 12.5, weight: .semibold, design: .rounded)
                )
                .foregroundColor(musicManager.isFetchingLyrics ? .white.opacity(0.7) : .white)
                .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0.75)
                .lineLimit(isLongCurrent ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 8).combined(with: .opacity),
                        removal: .offset(y: -8).combined(with: .opacity)
                    )
                )
                .id("current_\(lyricIndex)_\(displayCurrent)")

            // NEXT LYRIC: Smaller, subtle, underneath preview
            if !next.isEmpty {
                Text(next)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0.75)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 6).combined(with: .opacity),
                            removal: .offset(y: -6).combined(with: .opacity)
                        )
                    )
                    .id("next_\(lyricIndex)_\(next)")
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: lyricIndex)
        .clipped()
    }
}
