//
//  ConversationManager.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import AVFoundation
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
public final class ConversationManager: NSObject, ObservableObject, RealtimeAIProviderDelegate, AudioStreamManagerDelegate, VoiceActivityDelegate {
    public static let shared = ConversationManager()

    @Published public var state: ConversationState = .idle
    @Published public var audioLevel: Float = 0.0
    @Published public var isSessionActive: Bool = false

    public let captionManager = CaptionManager.shared
    private let audioStreamManager = AudioStreamManager()
    private let voiceActivityManager = VoiceActivityManager()
    private var aiProvider: (any RealtimeAIProvider) = GeminiLiveProvider()

    private var turnResetTask: Task<Void, Never>?

    private override init() {
        super.init()
        audioStreamManager.delegate = self
        voiceActivityManager.delegate = self
        aiProvider.delegate = self
    }

    // MARK: - Toggle & Session Control
    public func toggleConversationMode() {
        if isSessionActive {
            stopConversation()
        } else {
            Task {
                await startConversation()
            }
        }
    }

    public func startConversation() async {
        guard !isSessionActive else { return }

        // 1. Check & Request Microphone Permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authStatus {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                state = .error("Microphone permission denied")
                Defaults[.conversationModeEnabled] = false
                return
            }
        case .denied, .restricted:
            state = .error("Microphone permission required in System Settings")
            Defaults[.conversationModeEnabled] = false
            return
        case .authorized:
            break
        @unknown default:
            break
        }

        // 2. Validate API Key
        let apiKey = AIConfiguration.shared.getApiKey()
        guard !apiKey.isEmpty else {
            state = .error("Gemini API key missing in Settings")
            Defaults[.conversationModeEnabled] = false
            return
        }

        // 3. Connect Realtime Provider & Audio Streams
        isSessionActive = true
        Defaults[.conversationModeEnabled] = true
        state = .listening
        captionManager.clear()
        voiceActivityManager.reset()

        do {
            try await aiProvider.connect()
            try audioStreamManager.startCapture()
        } catch {
            isSessionActive = false
            Defaults[.conversationModeEnabled] = false
            state = .error("Connection error: \(error.localizedDescription)")
            audioStreamManager.stopAll()
            aiProvider.disconnect()
        }
    }

    public func stopConversation() {
        guard isSessionActive else {
            state = .idle
            return
        }

        isSessionActive = false
        Defaults[.conversationModeEnabled] = false
        turnResetTask?.cancel()

        // Clean up resources immediately
        audioStreamManager.stopAll()
        aiProvider.disconnect()
        voiceActivityManager.reset()
        audioLevel = 0.0
        state = .idle
    }

    public func interruptAssistant() {
        audioStreamManager.stopPlayback()
        captionManager.commitTurn()
        state = .listening
    }

    // MARK: - RealtimeAIProviderDelegate
    nonisolated public func providerDidConnect(_ provider: any RealtimeAIProvider) {
        Task { @MainActor in
            self.state = .listening
        }
    }

    nonisolated public func providerDidDisconnect(_ provider: any RealtimeAIProvider, error: Error?) {
        Task { @MainActor in
            if self.isSessionActive {
                if let error = error {
                    self.state = .error("Disconnected: \(error.localizedDescription)")
                } else {
                    self.state = .disconnected
                }
            }
        }
    }

    nonisolated public func provider(_ provider: any RealtimeAIProvider, didReceiveServerAudio data: Data) {
        Task { @MainActor in
            self.turnResetTask?.cancel()
            self.state = .assistantSpeaking
            self.audioStreamManager.playAudioChunk(data)
        }
    }

    nonisolated public func provider(_ provider: any RealtimeAIProvider, didReceiveServerText text: String) {
        Task { @MainActor in
            self.captionManager.appendAIText(text)
        }
    }

    nonisolated public func provider(_ provider: any RealtimeAIProvider, didDetectInterruption: Bool) {
        Task { @MainActor in
            // Server detected user barge-in!
            self.audioStreamManager.stopPlayback()
            self.captionManager.commitTurn()
            self.state = .userSpeaking
        }
    }

    nonisolated public func providerDidCompleteTurn(_ provider: any RealtimeAIProvider) {
        Task { @MainActor in
            self.turnResetTask?.cancel()
            self.turnResetTask = Task { @MainActor in
                // Give user a moment to finish listening/reading before returning to ready listening
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled, self.isSessionActive else { return }
                self.captionManager.commitTurn()
                self.state = .listening
            }
        }
    }

    nonisolated public func provider(_ provider: any RealtimeAIProvider, didEncounterError message: String) {
        Task { @MainActor in
            self.state = .error(message)
        }
    }

    // MARK: - AudioStreamManagerDelegate
    nonisolated public func audioStreamDidProduceMicChunk(_ data: Data) {
        if isSessionActive {
            aiProvider.sendAudioChunk(data)
        }
    }

    nonisolated public func audioStreamDidUpdateFloatSamples(_ samples: [Float]) {
        voiceActivityManager.processAudioBuffer(samples: samples)
    }

    nonisolated public func audioStreamPlaybackDidFinish() {
        Task { @MainActor in
            if self.state == .assistantSpeaking {
                self.state = .listening
            }
        }
    }

    nonisolated public func audioStreamDidFail(error: Error) {
        Task { @MainActor in
            self.state = .error("Audio device failure: \(error.localizedDescription)")
            self.stopConversation()
        }
    }

    // MARK: - VoiceActivityDelegate
    nonisolated public func voiceActivityDidDetectSpeech() {
        Task { @MainActor in
            guard self.isSessionActive else { return }

            // Local Barge-In: If user starts speaking while assistant is speaking, cut audio immediately!
            if self.state == .assistantSpeaking {
                self.audioStreamManager.stopPlayback()
                self.captionManager.commitTurn()
            }

            self.turnResetTask?.cancel()
            self.state = .userSpeaking
        }
    }

    nonisolated public func voiceActivityDidDetectSilence() {
        Task { @MainActor in
            guard self.isSessionActive else { return }

            if self.state == .userSpeaking {
                self.state = .thinking
            }
        }
    }

    nonisolated public func voiceActivityUpdateLevel(_ level: Float) {
        Task { @MainActor in
            self.audioLevel = level
        }
    }
}
