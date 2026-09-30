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

    // Realtime concurrency flags
    private nonisolated(unsafe) var isStreamingActive: Bool = false
    private nonisolated(unsafe) var activeAIProvider: (any RealtimeAIProvider)?
    private nonisolated(unsafe) var isAssistantSpeaking: Bool = false
    private nonisolated(unsafe) var isServerGenerating: Bool = false

    private var turnResetTask: Task<Void, Never>?
    private var guardCooldownTask: Task<Void, Never>?

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
            state = .error("API Key Required: Enter in Settings (⌘ ,)")
            Defaults[.conversationModeEnabled] = false
            DispatchQueue.main.async {
                SettingsWindowController.shared.showWindow()
            }
            return
        }

        // 3. Connect Realtime Provider & Audio Streams
        isSessionActive = true
        isStreamingActive = true
        isAssistantSpeaking = false
        isServerGenerating = false
        activeAIProvider = aiProvider
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
        isStreamingActive = false
        isAssistantSpeaking = false
        isServerGenerating = false
        activeAIProvider = nil
        Defaults[.conversationModeEnabled] = false
        turnResetTask?.cancel()
        guardCooldownTask?.cancel()

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
        isAssistantSpeaking = false
        isServerGenerating = false
        guardCooldownTask?.cancel()
        turnResetTask?.cancel()
        audioLevel = 0.0
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
        self.isAssistantSpeaking = true
        self.isServerGenerating = true
        self.audioStreamManager.playAudioChunk(data)

        // Compute peak / RMS audio level of incoming PCM audio for the visualizer
        let sampleCount = data.count / MemoryLayout<Int16>.size
        var level: Float = 0.0
        if sampleCount > 0 {
            data.withUnsafeBytes { raw in
                if let ptr = raw.bindMemory(to: Int16.self).baseAddress {
                    var sum: Float = 0
                    let strideStep = max(1, sampleCount / 64)
                    var count = 0
                    for i in stride(from: 0, through: sampleCount - 1, by: strideStep) {
                        let val = Float(ptr[i]) / 32768.0
                        sum += val * val
                        count += 1
                    }
                    let rms = sqrt(sum / Float(max(1, count)))
                    level = min(1.0, rms * 4.0)
                }
            }
        }

        Task { @MainActor in
            self.turnResetTask?.cancel()
            self.guardCooldownTask?.cancel()
            self.audioLevel = level
            if self.state != .assistantSpeaking {
                self.state = .assistantSpeaking
            }
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
            self.isAssistantSpeaking = false
            self.isServerGenerating = false
            self.guardCooldownTask?.cancel()
            self.turnResetTask?.cancel()
            self.audioLevel = 0.0
            self.state = .userSpeaking
        }
    }

    nonisolated public func providerDidCompleteTurn(_ provider: any RealtimeAIProvider) {
        self.isServerGenerating = false
        Task { @MainActor in
            // If audio player already drained all buffers, initiate return to listening
            if !self.audioStreamManager.isPlaying {
                self.scheduleReturnToListening()
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
        guard isStreamingActive else { return }
        // CRITICAL ACOUSTIC SHIELD: Never forward mic audio to Gemini while assistant is generating or speaking!
        // This completely prevents speaker-to-mic acoustic feedback loops and non-English hallucinations.
        guard !isAssistantSpeaking else { return }
        activeAIProvider?.sendAudioChunk(data)
    }

    nonisolated public func audioStreamDidUpdateFloatSamples(_ samples: [Float]) {
        guard !isAssistantSpeaking else {
            // Suppress VAD processing completely while assistant audio is playing through Mac speakers
            return
        }
        voiceActivityManager.processAudioBuffer(samples: samples)
    }

    nonisolated public func audioStreamPlaybackDidFinish() {
        Task { @MainActor in
            // Only transition back to listening if the server is also finished sending chunks
            if !self.isServerGenerating {
                self.scheduleReturnToListening()
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
            guard !self.isAssistantSpeaking else { return }

            self.turnResetTask?.cancel()
            self.guardCooldownTask?.cancel()

            // If previous assistant response exists, archive it now so user sees a clean slate
            if !self.captionManager.currentAIText.isEmpty {
                self.captionManager.commitTurn()
            }

            self.state = .userSpeaking
        }
    }

    nonisolated public func voiceActivityDidDetectSilence() {
        Task { @MainActor in
            guard self.isSessionActive else { return }
            guard !self.isAssistantSpeaking else { return }

            if self.state == .userSpeaking {
                self.state = .thinking
                // Flush any trailing sub-100ms buffered audio so the user's final words are not cut off
                self.audioStreamManager.flushMicBuffer()
                self.activeAIProvider?.commitTurn()
            }
        }
    }

    nonisolated public func voiceActivityUpdateLevel(_ level: Float) {
        Task { @MainActor in
            // Only drive visualizer from mic if assistant is not currently speaking
            if !self.isAssistantSpeaking {
                self.audioLevel = level
            }
        }
    }

    // MARK: - Cooldown Guard Transition
    private func scheduleReturnToListening() {
        guardCooldownTask?.cancel()
        guardCooldownTask = Task { @MainActor in
            // 400ms acoustic guard delay: lets room reverb and speaker acoustic decay settle before unmuting mic & VAD
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, self.isSessionActive else { return }

            // Verify server has not started another turn and player is truly quiet
            guard !self.isServerGenerating && !self.audioStreamManager.isPlaying else { return }

            self.isAssistantSpeaking = false
            self.audioLevel = 0.0

            if self.state == .assistantSpeaking || self.state == .thinking {
                self.state = .listening
            }

            // Keep the assistant's caption on-screen for 2.5 seconds so the user can read it comfortably
            self.turnResetTask?.cancel()
            self.turnResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled, self.isSessionActive else { return }
                self.captionManager.commitTurn()
            }
        }
    }
}
