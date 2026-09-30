//
//  ConversationState.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Foundation

public enum ConversationState: Equatable, Sendable {
    case idle
    case listening
    case userSpeaking
    case thinking
    case assistantSpeaking
    case error(String)
    case disconnected

    public var statusDescription: String {
        switch self {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening…"
        case .userSpeaking:
            return "Listening to you…"
        case .thinking:
            return "Thinking…"
        case .assistantSpeaking:
            return "Speaking…"
        case .error(let message):
            return message
        case .disconnected:
            return "Offline"
        }
    }

    public var systemIcon: String {
        switch self {
        case .idle:
            return "waveform"
        case .listening:
            return "mic.fill"
        case .userSpeaking:
            return "waveform.and.mic"
        case .thinking:
            return "sparkles"
        case .assistantSpeaking:
            return "speaker.wave.2.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "wifi.slash"
        }
    }

    public var isConversing: Bool {
        switch self {
        case .userSpeaking, .thinking, .assistantSpeaking:
            return true
        default:
            return false
        }
    }
}
