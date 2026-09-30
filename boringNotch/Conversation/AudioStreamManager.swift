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

    private var inputEngine: AVAudioEngine?
    private var outputEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?

    private var isRecording: Bool = false
    private var isPlayingAudio: Bool = false
    private let audioQueue = DispatchQueue(label: "theboringteam.boringnotch.audiomanager", qos: .userInteractive)

    public var isCapturing: Bool { isRecording }
    public var isPlaying: Bool { isPlayingAudio }

    public init() {
        // Output format from Gemini Live: 24kHz Mono 16-bit PCM
        playbackFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)
    }

    // MARK: - Microphone Streaming
    public func startCapture() throws {
        try audioQueue.sync {
            guard !isRecording else { return }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                throw NSError(domain: "AudioStreamManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid mic sample rate"])
            }

            self.inputEngine = engine
            let bufferSize: AVAudioFrameCount = 1024

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
                guard let self = self else { return }

                guard let floatChannels = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                let channelCount = Int(buffer.format.channelCount)
                guard frameLength > 0 else { return }

                // 1. Extract samples (average to mono if multi-channel)
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

                // 2. Downsample linearly to 16,000 Hz Int16 PCM for Gemini
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
            self.isRecording = true
        }
    }

    public func stopCapture() {
        audioQueue.sync {
            guard isRecording else { return }
            isRecording = false
            if let engine = inputEngine {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
            inputEngine = nil
        }
    }

    // MARK: - Audio Playback
    public func playAudioChunk(_ pcmData: Data) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupOutputEngineIfNeeded()

            guard let engine = self.outputEngine,
                  let player = self.playerNode,
                  let format = self.playbackFormat else { return }

            let frameCount = UInt32(pcmData.count / 2)
            guard frameCount > 0,
                  let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

            pcmBuffer.frameLength = frameCount
            if let channelData = pcmBuffer.int16ChannelData {
                pcmData.withUnsafeBytes { rawBufferPointer in
                    if let baseAddress = rawBufferPointer.baseAddress {
                        memcpy(channelData[0], baseAddress, Int(frameCount) * 2)
                    }
                }
            }

            self.isPlayingAudio = true
            if !engine.isRunning {
                try? engine.start()
            }

            player.scheduleBuffer(pcmBuffer, completionHandler: nil)

            if !player.isPlaying {
                player.play()
            }
        }
    }

    private func setupOutputEngineIfNeeded() {
        guard outputEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        if let format = playbackFormat {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        try? engine.start()
        player.play()

        self.outputEngine = engine
        self.playerNode = player
    }

    public func stopPlayback() {
        audioQueue.async { [weak self] in
            guard let self = self, let player = self.playerNode else { return }
            player.stop()
            self.isPlayingAudio = false
            player.play()
        }
    }

    public func stopAll() {
        stopCapture()
        stopPlayback()
        audioQueue.sync {
            outputEngine?.stop()
            outputEngine = nil
            playerNode = nil
        }
    }
}
