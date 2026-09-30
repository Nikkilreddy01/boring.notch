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

    @State private var isExpanded: Bool = false
    @State private var pauseInactivityTask: Task<Void, Never>?
    @State private var isTimedOut: Bool = false

    private let targetWidth: CGFloat = 390

    private var hasPhysicalNotch: Bool {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return (screen?.safeAreaInsets.top ?? 0) > 0
    }

    private var notchHeight: CGFloat {
        hasPhysicalNotch ? vm.effectiveClosedNotchHeight : 0
    }

    var body: some View {
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

            let isLongCurrent = displayCurrent.count > 34
            let contentHeight: CGFloat = isLongCurrent ? 56 : 42
            let currentWidth: CGFloat = isExpanded && !isTimedOut ? targetWidth : vm.closedNotchSize.width
            let currentHeight: CGFloat = isExpanded && !isTimedOut ? (notchHeight + contentHeight) : vm.effectiveClosedNotchHeight

            ZStack(alignment: .top) {
                // Continuous Liquid Glass Notch Surface (Zero gap, anchored directly to top bezel)
                NotchShape(topCornerRadius: 6, bottomCornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        NotchShape(topCornerRadius: 6, bottomCornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)

                // Content inside the Liquid Glass Notch
                VStack(spacing: 0) {
                    // Physical Camera Notch Cutout Space (untouched hardware)
                    if notchHeight > 0 {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: vm.closedNotchSize.width - 20, height: notchHeight)
                    }

                    // Lower area: Lyrics Row directly below the camera notch
                    if isExpanded && !isTimedOut {
                        HStack(spacing: 12) {
                            // LEFT: Album Artwork (Circular with subtle highlight and shadow)
                            albumArtView

                            // CENTER: Current + Next Lyrics (Vertical Flow Transition)
                            lyricContentView(displayCurrent: displayCurrent, next: next, lyricIndex: lyricIndex)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // RIGHT: Existing Music Indicator with Adaptive Artwork Accent
                            rightIndicatorView
                        }
                        .padding(.horizontal, 16)
                        .frame(height: contentHeight)
                        .opacity(isExpanded && !isTimedOut ? 1 : 0)
                        .offset(y: isExpanded && !isTimedOut ? 0 : -6)
                        .clipped()
                    }
                }
            }
            .frame(width: currentWidth, height: currentHeight)
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isExpanded)
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isTimedOut)
            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: contentHeight)
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
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2.5, x: 0, y: 1)
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

    // MARK: - Lyric Content View (Current + Next, Vertical Flow Transition)
    @ViewBuilder
    private func lyricContentView(displayCurrent: String, next: String, lyricIndex: Int) -> some View {
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
                .foregroundColor(musicManager.isFetchingLyrics ? .white.opacity(0.65) : .white)
                .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0.75)
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
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0.75)
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
