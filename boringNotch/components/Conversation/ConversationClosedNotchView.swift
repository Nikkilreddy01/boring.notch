//
//  ConversationClosedNotchView.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Defaults
import SwiftUI

struct ConversationClosedNotchView: View {
    @ObservedObject var conversationManager = ConversationManager.shared
    @ObservedObject var captionManager = CaptionManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Left Status & Waveform Indicator
            statusIndicator

            // Live Caption Area
            if Defaults[.conversationCaptionsEnabled] {
                captionArea
            } else {
                Text(conversationManager.state.statusDescription)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer(minLength: 0)

            // Right Quick Action / Mic Indicator
            actionPill
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: max(28, vm.effectiveClosedNotchHeight))
    }

    // MARK: - Status Indicator (Live Waveform)
    private var statusIndicator: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(waveformColor)
                    .frame(
                        width: 2.5,
                        height: barHeight(for: index)
                    )
            }
        }
        .frame(width: 20, height: 18)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.6), value: conversationManager.audioLevel)
    }

    private var waveformColor: Color {
        switch conversationManager.state {
        case .listening:
            return .cyan.opacity(0.85)
        case .userSpeaking:
            return .green
        case .thinking:
            return .orange
        case .assistantSpeaking:
            return .purple
        case .error:
            return .red
        default:
            return .white.opacity(0.5)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard conversationManager.state == .userSpeaking || conversationManager.state == .assistantSpeaking else {
            return 4.0
        }
        let level = CGFloat(conversationManager.audioLevel)
        let multipliers: [CGFloat] = [0.6, 1.0, 0.8, 0.4]
        let baseHeight: CGFloat = 4.0
        let maxHeight: CGFloat = 16.0
        return min(max(baseHeight, baseHeight + (maxHeight - baseHeight) * level * multipliers[index]), maxHeight)
    }

    // MARK: - Live Caption Area
    private var captionArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            if conversationManager.state == .assistantSpeaking || !captionManager.currentAIText.isEmpty {
                HStack(spacing: 4) {
                    Text("🤖")
                        .font(.system(size: 10))
                    Text(captionManager.currentAIText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            } else if conversationManager.state == .userSpeaking || !captionManager.currentUserText.isEmpty {
                HStack(spacing: 4) {
                    Text("🎙️")
                        .font(.system(size: 10))
                    Text(captionManager.currentUserText.isEmpty ? "Listening to you…" : captionManager.currentUserText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                .transition(.opacity)
            } else {
                Text(conversationManager.state.statusDescription)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .animation(.smooth(duration: 0.2), value: captionManager.currentAIText)
    }

    // MARK: - Action / Mode Pill
    private var actionPill: some View {
        Button(action: {
            conversationManager.toggleConversationMode()
        }) {
            Image(systemName: conversationManager.state.systemIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(conversationManager.isSessionActive ? .white : .gray)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
