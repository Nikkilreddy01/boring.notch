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
    @ObservedObject var conversationManager = ConversationManager.shared
    @ObservedObject var captionManager = CaptionManager.shared
    @EnvironmentObject var vm: BoringViewModel

    @State private var isExpanded: Bool = false
    @State private var isTimedOut: Bool = false
    @State private var pauseInactivityTask: Task<Void, Never>?

    @State private var isPointerInside = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isConversationActive: Bool {
        Defaults[.conversationModeEnabled] && (conversationManager.state.isConversing || !captionManager.currentAIText.isEmpty || !captionManager.currentUserText.isEmpty)
    }

    private var isMusicActive: Bool {
        Defaults[.minimalLyricsMode] && (musicManager.isPlaying || !musicManager.isPlayerIdle)
    }

    private var isVisible: Bool {
        if isConversationActive { return true }
        return isExpanded && !isTimedOut && !isDismissed
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.82)
    }

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
        TimelineView(.animation(minimumInterval: 0.1, paused: !musicManager.isPlaying && !isConversationActive)) { timeline in
            lyricsBody(at: timeline.date)
        }
    }

    @ViewBuilder
    private func lyricsBody(at date: Date) -> some View {
        let (current, next, lyricIndex) = musicManager.currentAndNextLyric(at: musicManager.estimatedPlaybackPosition(at: date))

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
        let isLongCurrent = isConversationActive ? true : (displayCurrent.count > 34)
        let barHeight: CGFloat = isLongCurrent ? 52 : 46
        let cornerRadius: CGFloat = isLongCurrent ? 20 : 23

        VStack(alignment: .center, spacing: 0) {
            // 1. Untouched Physical Camera Notch Area (Standard Black Mask)
            if notchHeight > 0 {
                ZStack {
                    NotchShape(
                        topCornerRadius: cornerRadiusInsets.closed.top,
                        bottomCornerRadius: cornerRadiusInsets.closed.bottom
                    )
                    .fill(Color.black)
                    .frame(width: vm.closedNotchSize.width, height: notchHeight)

                    // Wings outside the camera
                    HStack {
                        if musicManager.isPlaying {
                            Image(nsImage: musicManager.albumArt)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 14, height: 14)
                                .clipShape(Circle())
                                .padding(.leading, 8)
                        }
                        Spacer()
                        if Defaults[.conversationModeEnabled] {
                            Image(systemName: conversationManager.state.systemIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(conversationManager.isSessionActive ? .cyan : .gray)
                                .padding(.trailing, 8)
                        }
                    }
                    .frame(width: vm.closedNotchSize.width, height: notchHeight)
                }
                .zIndex(1)
            }

            // 2. Clear Gap Between Physical Notch and Floating Bar
            Color.clear
                .frame(width: targetWidth, height: (notchHeight > 0 ? 8 : 12))

            // 3. Separate Floating Liquid Glass Bar Below the Notch (Unobstructed by camera!)
            ZStack {
                if isConversationActive {
                    // CONVERSATION VIEW (Active Voice Partner)
                    HStack(spacing: 10) {
                        conversationOrbView

                        conversationCaptionView
                            .frame(maxWidth: .infinity, alignment: .leading)

                        conversationActionPill
                    }
                    .padding(.horizontal, 14)
                    .frame(width: targetWidth, height: barHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // MINIMAL LYRICS VIEW
                    HStack(spacing: 12) {
                        albumArtView

                        lyricContentView(displayCurrent: displayCurrent, next: resolvedNext, lyricIndex: lyricIndex, isLongCurrent: isLongCurrent)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        rightIndicatorView
                    }
                    .padding(.horizontal, 14)
                    .frame(width: targetWidth, height: barHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(width: targetWidth, height: barHeight)
            .background(
                liquidGlassBackground(cornerRadius: cornerRadius)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 7)
            .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
            .scaleEffect(x: isVisible || reduceMotion ? 1 : 0.28, y: isVisible || reduceMotion ? 1 : 0.08, anchor: .top)
            .offset(y: reduceMotion ? 0 : (isVisible ? dragOffset : -(notchHeight > 0 ? 24 : 12)))
            .opacity(isVisible && !isPointerInside ? 1 : 0)
            .animation(motion, value: isVisible)
            .animation(.easeInOut(duration: 0.2), value: isConversationActive)
            .animation(.easeInOut(duration: 0.18), value: isPointerInside)
            .background {
                LyricsPointerRegion(visible: isVisible, onHover: { isPointerInside = $0 })
            }
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        if value.translation.height < 0 {
                            dragOffset = value.translation.height * 0.4
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -14 || value.predictedEndTranslation.height < -25 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isDismissed = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .frame(width: targetWidth, alignment: .top)
        .onAppear {
            if musicManager.isPlaying {
                isExpanded = true
            }
        }
        .onChange(of: musicManager.isPlaying) { _, playing in
            handlePlaybackChange(isPlaying: playing)
        }
    }

    // MARK: - Conversation Subviews
    private var conversationOrbView: some View {
        ZStack {
            Circle()
                .fill(orbColor.opacity(0.2))
                .frame(width: 28, height: 28)
                .scaleEffect(1.0 + CGFloat(conversationManager.audioLevel) * 0.3)

            Circle()
                .fill(orbColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Image(systemName: conversationManager.state.systemIcon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
        }
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.7), value: conversationManager.audioLevel)
    }

    private var orbColor: Color {
        switch conversationManager.state {
        case .listening:
            return .cyan
        case .userSpeaking:
            return .green
        case .thinking:
            return .orange
        case .assistantSpeaking:
            return .purple
        case .error:
            return .red
        default:
            return .gray
        }
    }

    private var conversationCaptionView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if conversationManager.state == .assistantSpeaking || !captionManager.currentAIText.isEmpty {
                HStack(spacing: 4) {
                    Text("🤖")
                        .font(.system(size: 11))
                    Text(captionManager.currentAIText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            } else if conversationManager.state == .userSpeaking || !captionManager.currentUserText.isEmpty {
                HStack(spacing: 4) {
                    Text("🎙️")
                        .font(.system(size: 11))
                    Text(captionManager.currentUserText.isEmpty ? "Listening to you…" : captionManager.currentUserText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(2)
                }
                .transition(.opacity)
            } else {
                Text(conversationManager.state.statusDescription)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .animation(.smooth(duration: 0.2), value: captionManager.currentAIText)
    }

    private var conversationActionPill: some View {
        Button(action: {
            if conversationManager.state == .assistantSpeaking {
                conversationManager.interruptAssistant()
            } else {
                conversationManager.toggleConversationMode()
            }
        }) {
            Image(systemName: conversationManager.state == .assistantSpeaking ? "hand.raised.fill" : conversationManager.state.systemIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Liquid Glass Substrate
    private func liquidGlassBackground(cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.36))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.28), location: 0.0),
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
                isDismissed = false
                isTimedOut = false
                isExpanded = true
            }
        } else {
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

    // MARK: - Lyric Content View
    @ViewBuilder
    private func lyricContentView(displayCurrent: String, next: String, lyricIndex: Int, isLongCurrent: Bool) -> some View {
        let isPersian = displayCurrent.unicodeScalars.contains { scalar in
            let v = scalar.value
            return v >= 0x0600 && v <= 0x06FF
        }

        VStack(alignment: .leading, spacing: 2) {
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

private struct LyricsPointerRegion: NSViewRepresentable {
    var visible: Bool
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> RegionView { RegionView() }

    func updateNSView(_ view: RegionView, context: Context) {
        view.visible = visible
        view.onHover = onHover
    }

    static func dismantleNSView(_ view: RegionView, coordinator: ()) { view.stop() }

    final class RegionView: NSView {
        var visible = false
        var onHover: ((Bool) -> Void)?
        private var timer: Timer?
        private var enteredAt: Date?
        private var revealed = false
        private var isCapturingDrag = false
        private weak var passthroughWindow: NSWindow?

        private let passthroughDelay: TimeInterval = 0.6
        private let grabZoneHeight: CGFloat = 10

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.updatePointer() }
            RunLoop.main.add(timer!, forMode: .common)
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            enteredAt = nil
            revealed = false
            isCapturingDrag = false
            onHover?(false)
            passthroughWindow?.ignoresMouseEvents = false
            passthroughWindow = nil
        }

        private func updatePointer() {
            guard let window else { return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            let pointer = NSEvent.mouseLocation
            let inside = visible && rect.contains(pointer)
            let inGrabZone = inside && pointer.y >= rect.maxY - grabZoneHeight
            let primaryButtonDown = NSEvent.pressedMouseButtons & 1 != 0

            if !inside {
                enteredAt = nil
                isCapturingDrag = false
            } else if enteredAt == nil {
                enteredAt = Date()
            }

            if inGrabZone && primaryButtonDown {
                isCapturingDrag = true
            } else if !primaryButtonDown {
                isCapturingDrag = false
            }

            let hoverDuration = Date().timeIntervalSince(enteredAt ?? Date())
            let shouldReveal = inside
            let shouldPassThrough = inside
                && hoverDuration >= passthroughDelay
                && !inGrabZone
                && !isCapturingDrag

            if revealed != shouldReveal {
                revealed = shouldReveal
                onHover?(revealed)
            }

            if shouldPassThrough {
                passthroughWindow = window
                window.ignoresMouseEvents = true
            } else if let previous = passthroughWindow {
                previous.ignoresMouseEvents = false
                passthroughWindow = nil
            }
        }
    }
}
