//
//  GeminiLiveProvider.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Foundation

public final class GeminiLiveProvider: NSObject, RealtimeAIProvider, URLSessionWebSocketDelegate, @unchecked Sendable {
    public weak var delegate: RealtimeAIProviderDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isSessionConnected: Bool = false
    private let sendQueue = DispatchQueue(label: "theboringteam.boringnotch.geminisend", qos: .userInteractive)

    public var isConnected: Bool {
        isSessionConnected
    }

    public override init() {
        super.init()
    }

    public func connect() async throws {
        disconnect()

        let apiKey = AIConfiguration.shared.getApiKey()
        guard !apiKey.isEmpty else {
            let errorMsg = "Gemini API key missing. Configure it in Settings."
            delegate?.provider(self, didEncounterError: errorMsg)
            throw NSError(domain: "GeminiLiveProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        let model = AIConfiguration.shared.currentModel
        let voice = AIConfiguration.shared.currentVoice
        let systemPrompt = AIConfiguration.shared.systemInstruction

        guard let endpointURL = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)") else {
            throw NSError(domain: "GeminiLiveProvider", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini WebSocket URL"])
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())

        let task = urlSession!.webSocketTask(with: endpointURL)
        self.webSocketTask = task
        task.resume()

        // 1. Send Setup payload immediately upon connection
        try await sendSetupMessage(model: model, voice: voice, systemInstruction: systemPrompt)

        self.isSessionConnected = true
        delegate?.providerDidConnect(self)

        // 2. Start receiving loop
        startReceiveLoop()
    }

    public func disconnect() {
        isSessionConnected = false
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    public func sendAudioChunk(_ data: Data) {
        guard isSessionConnected, let task = webSocketTask else { return }

        let base64String = data.base64EncodedString()
        let payload: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": base64String
                    ]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let message = URLSessionWebSocketTask.Message.data(jsonData)

        sendQueue.async {
            task.send(message) { _ in }
        }
    }

    public func sendTextMessage(_ text: String) {
        guard isSessionConnected, let task = webSocketTask else { return }

        let payload: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turnComplete": true
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let message = URLSessionWebSocketTask.Message.data(jsonData)

        sendQueue.async {
            task.send(message) { _ in }
        }
    }

    public func commitTurn() {
        guard isSessionConnected, let task = webSocketTask else { return }

        let payload: [String: Any] = [
            "clientContent": [
                "turnComplete": true
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let message = URLSessionWebSocketTask.Message.data(jsonData)

        sendQueue.async {
            task.send(message) { _ in }
        }
    }

    // MARK: - Private Setup Message
    private func sendSetupMessage(model: String, voice: String, systemInstruction: String) async throws {
        guard let task = webSocketTask else { return }

        let formattedModel = model.starts(with: "models/") ? model : "models/\(model)"

        let strictEnglishInstruction = """
        CRITICAL INSTRUCTION: You must strictly speak and respond ONLY in fluent, natural English. Under no circumstances should you ever speak, respond, or switch to any other language, even if background noise or audio input sounds like another language. Always reply in clear English. Keep your answers concise (1-2 short sentences) and natural for a voice conversation.

        """ + systemInstruction

        let setupPayload: [String: Any] = [
            "setup": [
                "model": formattedModel,
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": voice
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": strictEnglishInstruction]
                    ]
                ],
                "outputAudioTranscription": [String: Any]()
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: setupPayload)
        try await task.send(.data(jsonData))
    }

    // MARK: - Continuous Receive Loop
    private func startReceiveLoop() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            guard let self = self, self.isSessionConnected else { return }

            switch result {
            case .success(let message):
                self.handleWebSocketMessage(message)
                self.startReceiveLoop() // Continue receiving next message
            case .failure(let error):
                self.isSessionConnected = false
                self.delegate?.providerDidDisconnect(self, error: error)
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        let rawData: Data?
        switch message {
        case .data(let data):
            rawData = data
        case .string(let text):
            rawData = text.data(using: .utf8)
        @unknown default:
            rawData = nil
        }

        guard let data = rawData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Check for error payload
        if let error = json["error"] as? [String: Any] {
            let errorMsg = (error["message"] as? String) ?? "Unknown Gemini Live error"
            delegate?.provider(self, didEncounterError: errorMsg)
            return
        }

        // Check for serverContent
        if let serverContent = json["serverContent"] as? [String: Any] {
            var handledText = false

            // 1. Live AI Speech Transcription
            if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
               let text = outputTranscription["text"] as? String, !text.isEmpty {
                handledText = true
                delegate?.provider(self, didReceiveServerText: text)
            }

            // 2. Live User Speech Recognition
            if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
               let userText = inputTranscription["text"] as? String, !userText.isEmpty {
                DispatchQueue.main.async {
                    CaptionManager.shared.setUserText(userText)
                }
            }

            // 3. Interruption flag
            if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
                delegate?.provider(self, didDetectInterruption: true)
            }

            // 4. Model Turn (Text and Audio parts)
            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    // Text transcript chunk (fallback if not already emitted by outputTranscription)
                    if !handledText, let text = part["text"] as? String, !text.isEmpty {
                        delegate?.provider(self, didReceiveServerText: text)
                    }

                    // Audio chunk (base64 PCM)
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let base64Audio = inlineData["data"] as? String,
                       let audioBytes = Data(base64Encoded: base64Audio) {
                        delegate?.provider(self, didReceiveServerAudio: audioBytes)
                    }
                }
            }

            // 5. Turn complete flag
            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                delegate?.providerDidCompleteTurn(self)
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isSessionConnected = false
        delegate?.providerDidDisconnect(self, error: nil)
    }
}
