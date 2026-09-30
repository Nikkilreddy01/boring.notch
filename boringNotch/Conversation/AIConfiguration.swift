//
//  AIConfiguration.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Defaults
import Foundation

public final class AIConfiguration: @unchecked Sendable {
    public static let shared = AIConfiguration()

    public static let availableVoices = ["Puck", "Charon", "Kore", "Fenrir", "Aoede"]
    public static let availableModels = [
        "gemini-3.8-live",
        "gemini-3-flash-preview",
        "gemini-2.5-flash"
    ]

    private init() {}

    // MARK: - API Key Management (Stored directly in Defaults, zero Keychain prompts)
    public func getApiKey() -> String {
        let key = Defaults[.geminiApiKey].trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            return key
        }

        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    public func setApiKey(_ key: String) {
        Defaults[.geminiApiKey] = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func deleteApiKey() {
        Defaults[.geminiApiKey] = ""
    }

    // MARK: - Model & Voice Options
    public var currentModel: String {
        Defaults[.conversationModelName]
    }

    public var currentVoice: String {
        Defaults[.conversationVoiceName]
    }

    public var systemInstruction: String {
        let custom = Defaults[.conversationSystemPrompt].trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }
        return "You are a concise, helpful voice conversation partner living inside the user's macOS notch. You must always speak and reply in English only. Keep answers brief (1-2 short sentences) and completely natural for voice."
    }
}
