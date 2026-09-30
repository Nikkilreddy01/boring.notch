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

    // Audio Engines
    private var inputEngine: AVAudioEngine?
    private var outputEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private var audioConverter: AVAudioConverter?
    private var targetMicFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat?

    private var isRecording: Bool = false
    private var isPlayingAudio: Bool = false
    private let audioQueue = DispatchQueue(label: "theboringteam.boringnotch.audiomanager", qos: .userInteractive)

    public var isCapturing: Bool {
        isRecording
    }

    public var isPlaying: Bool {
        isPlayingAudio
    }

    public init() {
        // Output format from Gemini Live: 24kHz Mono 16-bit PCM
        playbackFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)
        // Mic input format to Gemini Live: 16kHz Mono 16-bit PCM
        targetMicFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)
    }

    // MARK: - Microphone Streaming
    public func startCapture() throws {
        audioQueue.sync {
            guard !isRecording else { return }

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                return
            }

            guard let targetFormat = self.targetMicFormat,
                  let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                return
            }

            self.audioConverter = converter
            self.inputEngine = engine

            let bufferSize: AVAudioFrameCount = 1024
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
                guard let self = self else { return }

                // 1. Extract float samples for VAD & UI visualizer
                if let floatChannel = buffer.floatChannelData {
                    let frameCount = Int(buffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: floatChannel[0], count: frameCount))
                    self.delegate?.audioStreamDidUpdateFloatSamples(samples)
                }

                // 2. Convert to 16kHz Int16 PCM for Gemini
                self.convertAndStream(buffer: buffer)
            }

            do {
                try engine.start()
                self.isRecording = true
            } catch {
                self.delegate?.audioStreamDidFail(error: error)
            }
        }
    }

    private func convertAndStream(buffer: AVAudioPCMBuffer) {
        guard let converter = self.audioConverter, let targetFormat = self.targetMicFormat else { return }

        let sampleRateRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio + 10)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var hasProvidedInput = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if !hasProvidedInput {
                hasProvidedInput = true
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        if status == .haveData || status == .inputRanDry {
            if convertedBuffer.frameLength > 0, let int16Data = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * 2 // 2 bytes per sample
                let data = Data(bytes: int16Data[0], count: byteCount)
                self.delegate?.audioStreamDidProduceMicChunk(data)
            }
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
            audioConverter = nil
        }
    }

    // MARK: - Audio Playback (Speaker Output)
    public func playAudioChunk(_ pcmData: Data) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }

            self.setupOutputEngineIfNeeded()

            guard let engine = self.outputEngine,
                  let player = self.playerNode,
                  let format = self.playbackFormat else { return }

            let frameCount = UInt32(pcmData.count / 2) // 16-bit mono = 2 bytes per frame
            guard frameCount > 0,
                  let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

            pcmBuffer.frameLength = frameCount
            if let channelData = pcmBuffer.int16ChannelData {
                pcmData.withUnsafeBytes { rawBufferPointer in
                    if let baseAddress = rawBufferPointer.baseAddress {
                        memcpy(channelData[0], baseAddress, pcmData.count)
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

    /// Instant Barge-in / Interruption: Stops speaker output and flushes all queued audio buffers
    public func stopPlayback() {
        audioQueue.async { [weak self] in
            guard let self = self, let player = self.playerNode else { return }
            player.stop() // Immediately flushes queued buffers
            self.isPlayingAudio = false
            player.play() // Ready for next turn
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
