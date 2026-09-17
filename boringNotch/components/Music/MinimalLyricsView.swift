//
//  MinimalLyricsView.swift
//  boringNotch
//
//  Created by opencode on 2026-09-17.
//

import AppKit
import Defaults
import SwiftUI

struct CircularBeatIndicator: View {
    let isPlaying: Bool
    var tintColor: Color = .white
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            // Subtle outer pulsing ring
            Circle()
                .stroke(
                    tintColor.opacity(isPlaying ? (isPulsing ? 0.35 : 0.75) : 0.2),
                    lineWidth: 1.5
                )
                .frame(width: 13, height: 13)
                .scaleEffect(isPlaying ? (isPulsing ? 1.15 : 0.88) : 0.88)

            // Subtle inner beat core
            Circle()
                .fill(
                    tintColor.opacity(isPlaying ? (isPulsing ? 0.95 : 0.55) : 0.25)
                )
                .frame(width: 5.5, height: 5.5)
                .scaleEffect(isPlaying ? (isPulsing ? 1.1 : 0.85) : 0.85)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            if isPlaying {
                startPulsing()
            }
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                startPulsing()
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    isPulsing = false
                }
            }
        }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

struct MinimalLyricsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared

    private var hasPhysicalNotch: Bool {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        return (screen?.safeAreaInsets.top ?? 0) > 0
    }

    private var contentWidth: CGFloat {
        max(380, vm.closedNotchSize.width + 120)
    }

    var body: some View {
        VStack(spacing: 0) {
            // On physical notch screens, preserve the camera cutout hardware space
            if hasPhysicalNotch && vm.effectiveClosedNotchHeight > 0 {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
            }

            // Minimal Lyrics Bar
            HStack(spacing: 10) {
                // LEFT: Existing song/album artwork
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                // CENTER: Synchronized lyric line
                lyricContent
                    .frame(maxWidth: .infinity, alignment: .center)

                // RIGHT: Subtle circular beat indicator
                CircularBeatIndicator(
                    isPlaying: musicManager.isPlaying,
                    tintColor: Defaults[.playerColorTinting]
                        ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7)
                        : .white
                )
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Color.black.opacity(0.85))
        }
        .frame(width: contentWidth)
    }

    @ViewBuilder
    private var lyricContent: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let currentElapsed: Double = {
                guard musicManager.isPlaying else { return musicManager.elapsedTime }
                let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                return min(max(progressed, 0), musicManager.songDuration)
            }()

            let line: String = {
                if musicManager.isFetchingLyrics {
                    return "Loading lyrics…"
                }
                if !musicManager.syncedLyrics.isEmpty {
                    let synced = musicManager.lyricLine(at: currentElapsed).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !synced.isEmpty {
                        return synced
                    }
                }
                let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let firstLine = trimmed.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                    if !firstLine.isEmpty {
                        return firstLine
                    }
                }
                if !musicManager.songTitle.isEmpty {
                    return musicManager.songTitle + (musicManager.artistName.isEmpty ? "" : " • " + musicManager.artistName)
                }
                return "No lyrics found"
            }()

            let isPersian = line.unicodeScalars.contains { scalar in
                let v = scalar.value
                return v >= 0x0600 && v <= 0x06FF
            }

            Text(line)
                .font(
                    isPersian
                        ? .custom("Vazirmatn-Regular", size: 12)
                        : .system(size: 12.5, weight: .medium, design: .rounded)
                )
                .foregroundColor(
                    musicManager.isFetchingLyrics
                        ? Color.gray.opacity(0.7)
                        : Color.white.opacity(0.92)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .id(line)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: line)
        }
    }
}
