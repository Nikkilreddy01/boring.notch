//
//  VoiceActivityManager.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Accelerate
import Foundation

public protocol VoiceActivityDelegate: AnyObject {
    func voiceActivityDidDetectSpeech()
    func voiceActivityDidDetectSilence()
    func voiceActivityUpdateLevel(_ level: Float)
}

public final class VoiceActivityManager: @unchecked Sendable {
    public weak var delegate: VoiceActivityDelegate?

    public var speechThreshold: Float = 0.015
    public var silenceDurationThreshold: TimeInterval = 0.9

    private var isSpeaking: Bool = false
    private var lastSpeechTimestamp: Date = Date()
    private var currentLevel: Float = 0.0
    private let processingQueue = DispatchQueue(label: "theboringteam.boringnotch.vad", qos: .userInteractive)

    public init() {}

    public func processAudioBuffer(samples: [Float]) {
        guard !samples.isEmpty else { return }

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // 1. Calculate RMS using Accelerate framework vDSP
            var sumOfSquares: Float = 0
            vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(samples.count))
            let rms = sqrt(sumOfSquares / Float(samples.count))

            // 2. Smooth audio level for visualizer
            let smoothed = self.currentLevel * 0.7 + rms * 0.3
            self.currentLevel = smoothed

            DispatchQueue.main.async {
                self.delegate?.voiceActivityUpdateLevel(min(smoothed * 15.0, 1.0))
            }

            let now = Date()

            // 3. Speech onset / continuation
            if rms > self.speechThreshold {
                self.lastSpeechTimestamp = now
                if !self.isSpeaking {
                    self.isSpeaking = true
                    DispatchQueue.main.async {
                        self.delegate?.voiceActivityDidDetectSpeech()
                    }
                }
            } else {
                // 4. Silence detection
                if self.isSpeaking && now.timeIntervalSince(self.lastSpeechTimestamp) >= self.silenceDurationThreshold {
                    self.isSpeaking = false
                    DispatchQueue.main.async {
                        self.delegate?.voiceActivityDidDetectSilence()
                    }
                }
            }
        }
    }

    public func reset() {
        processingQueue.async { [weak self] in
            self?.isSpeaking = false
            self?.currentLevel = 0.0
            self?.lastSpeechTimestamp = Date()
        }
    }
}
