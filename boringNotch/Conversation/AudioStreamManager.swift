//
//  AudioStreamManager.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import AVFoundation
import Foundation

public protocol AudioStreamManagerDelegate: AnyObject {
    func audioStreamDidProduceMicChunk(_ data: Data)
    func audioStreamDidUpdateFloatSamples(_ samples: [Float])
    func audioStreamPlaybackDidFinish()
    func audioStreamDidFail(error: Error)
}

public final class AudioStreamManager: @unchecked Sendable {
    public weak var delegate: AudioStreamManagerDelegate?

    // Unified audio engine for simultaneous mic input and speaker output
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!

    private var isRecording: Bool = false
    private var isPlayingAudio: Bool = false
    private var pendingBufferCount: Int = 0
    private let audioQueue = DispatchQueue(label: "theboringteam.boringnotch.audiomanager", qos: .userInteractive)

    public var isCapturing: Bool { isRecording }
    public var isPlaying: Bool { isPlayingAudio }

    public init() {}

    // MARK: - Combined Capture & Playback Setup
    public func startCapture() throws {
        try audioQueue.sync {
            guard !isRecording else { return }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                throw NSError(domain: "AudioStreamManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid mic sample rate"])
            }

            self.audioEngine = engine
            self.playerNode = player
            self.pendingBufferCount = 0

            let bufferSize: AVAudioFrameCount = 1024
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
                guard let self = self else { return }
                guard let floatChannels = buffer.floatChannelData else { return }

                let frameLength = Int(buffer.frameLength)
                let channelCount = Int(buffer.format.channelCount)
                guard frameLength > 0 else { return }

                // 1. Mono float samples for energy VAD
                var monoSamples = [Float](repeating: 0, count: frameLength)
                if channelCount == 1 {
                    monoSamples = Array(UnsafeBufferPointer(start: floatChannels[0], count: frameLength))
                } else {
                    let ch0 = floatChannels[0]
                    let ch1 = floatChannels[1]
                    for i in 0..<frameLength {
                        monoSamples[i] = (ch0[i] + ch1[i]) * 0.5
                    }
                }

                self.delegate?.audioStreamDidUpdateFloatSamples(monoSamples)

                // 2. Downsample linearly to 16,000 Hz 16-bit PCM for Gemini
                let inSampleRate = buffer.format.sampleRate
                let targetSampleRate: Double = 16000.0
                let step = inSampleRate / targetSampleRate
                let outLength = max(1, Int(Double(frameLength) / step))

                var int16Data = Data(capacity: outLength * 2)
                for i in 0..<outLength {
                    let srcIndex = min(Int(Double(i) * step), frameLength - 1)
                    let clamped = max(-1.0, min(1.0, monoSamples[srcIndex]))
                    var sample16 = Int16(clamped * 32767.0)
                    withUnsafeBytes(of: &sample16) { bytes in
                        int16Data.append(contentsOf: bytes)
                    }
                }

                self.delegate?.audioStreamDidProduceMicChunk(int16Data)
            }

            engine.prepare()
            try engine.start()
            player.play()

            self.isRecording = true
        }
    }

    public func stopCapture() {
        audioQueue.sync {
            guard isRecording else { return }
            isRecording = false
            if let engine = audioEngine {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
            audioEngine = nil
            playerNode = nil
            pendingBufferCount = 0
            isPlayingAudio = false
        }
    }

    // MARK: - Audio Playback
    public func playAudioChunk(_ pcmData: Data) {
        audioQueue.async { [weak self] in
            guard let self = self,
                  self.audioEngine != nil,
                  let player = self.playerNode else { return }

            let frameCount = pcmData.count / 2
            guard frameCount > 0,
                  let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }

            pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
            guard let floatChannels = pcmBuffer.floatChannelData else { return }
            let channel0 = floatChannels[0]

            pcmData.withUnsafeBytes { raw in
                guard let int16Ptr = raw.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<frameCount {
                    channel0[i] = Float(int16Ptr[i]) / 32768.0
                }
            }

            self.isPlayingAudio = true
            self.pendingBufferCount += 1

            player.scheduleBuffer(pcmBuffer) { [weak self] in
                self?.audioQueue.async {
                    guard let self = self else { return }
                    self.pendingBufferCount = max(0, self.pendingBufferCount - 1)
                    if self.pendingBufferCount == 0 {
                        self.isPlayingAudio = false
                        self.delegate?.audioStreamPlaybackDidFinish()
                    }
                }
            }

            if !player.isPlaying {
                player.play()
            }
        }
    }

    public func stopPlayback() {
        audioQueue.async { [weak self] in
            guard let self = self, let player = self.playerNode else { return }
            player.stop()
            self.pendingBufferCount = 0
            self.isPlayingAudio = false
            player.play()
        }
    }

    public func stopAll() {
        stopCapture()
    }
}
