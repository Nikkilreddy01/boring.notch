//
//  ConversationView.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Defaults
import SwiftUI

struct ConversationView: View {
    @ObservedObject var conversationManager = ConversationManager.shared
    @ObservedObject var captionManager = CaptionManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Left Panel: Dynamic Visualizer & Controls
            visualizerControlPanel
                .frame(width: 170)

            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.vertical, 8)

            // Right Panel: Live Transcript & Conversation Turns
            transcriptPanel
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Visualizer & Controls
    private var visualizerControlPanel: some View {
        VStack(spacing: 10) {
            // Waveform Orb / Visualizer
            ZStack {
                Circle()
                    .fill(orbColor.opacity(0.15))
                    .frame(width: 54, height: 54)
                    .scaleEffect(1.0 + CGFloat(conversationManager.audioLevel) * 0.4)

                Circle()
                    .fill(orbColor)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: conversationManager.state.systemIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: orbColor.opacity(0.5), radius: 6, x: 0, y: 0)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: conversationManager.audioLevel)

            // Status Badge
            Text(conversationManager.state.statusDescription)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    conversationManager.toggleConversationMode()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: conversationManager.isSessionActive ? "stop.fill" : "play.fill")
                        Text(conversationManager.isSessionActive ? "Stop" : "Start")
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                .buttonStyle(.plain)

                if conversationManager.state == .assistantSpeaking {
                    Button(action: {
                        conversationManager.interruptAssistant()
                    }) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help("Interrupt AI")
                }

                Button(action: {
                    captionManager.clear()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Clear transcript")
            }
        }
        .frame(maxHeight: .infinity)
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

    // MARK: - Transcript Panel
    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if captionManager.turnsHistory.isEmpty && captionManager.currentUserText.isEmpty && captionManager.currentAIText.isEmpty {
                        emptyPromptView
                    } else {
                        ForEach(captionManager.turnsHistory) { turn in
                            turnCard(turn)
                        }

                        if !captionManager.currentUserText.isEmpty {
                            activeCard(role: "You", icon: "🎙️", text: captionManager.currentUserText, color: .green)
                        }

                        if !captionManager.currentAIText.isEmpty {
                            activeCard(role: "Gemini", icon: "🤖", text: captionManager.currentAIText, color: .purple)
                        }

                        Color.clear.frame(height: 1).id("bottomAnchor")
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: captionManager.currentAIText) {
                withAnimation {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
            }
        }
    }

    private var emptyPromptView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Continuous Voice Partner")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text("Speak naturally without pressing buttons. Ask questions, brainstorm, or translate in real time.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private func turnCard(_ turn: TurnItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(turn.role == .user ? "🎙️" : "🤖")
                .font(.system(size: 11))
            Text(turn.text)
                .font(.system(size: 12, weight: turn.role == .assistant ? .semibold : .regular, design: .rounded))
                .foregroundColor(turn.role == .assistant ? .white : .white.opacity(0.85))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(turn.role == .assistant ? Color.purple.opacity(0.12) : Color.white.opacity(0.06))
        )
    }

    private func activeCard(role: String, icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.15))
        )
    }
}
