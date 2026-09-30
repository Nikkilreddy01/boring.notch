//
//  AIConfiguration.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Foundation
import Security
import Defaults

public final class AIConfiguration: @unchecked Sendable {
    public static let shared = AIConfiguration()

    private let keychainService = "theboringteam.boringnotch"
    private let keychainAccount = "geminiApiKey"
    private let fallbackUserDefaultKey = "theboringteam.boringnotch.geminiApiKey"

    public static let availableVoices = ["Puck", "Charon", "Kore", "Fenrir", "Aoede"]
    public static let availableModels = [
        "gemini-3.8-live",
        "gemini-3-flash-preview",
        "gemini-2.5-flash"
    ]

    private init() {}

    // MARK: - API Key Management
    public func getApiKey() -> String {
        // 1. Try Keychain
        if let keychainKey = readFromKeychain(), !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return keychainKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Check Process Environment
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Fallback to UserDefaults
        if let udKey = UserDefaults.standard.string(forKey: fallbackUserDefaultKey), !udKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return udKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    public func setApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saveToKeychain(trimmed)
        UserDefaults.standard.set(trimmed, forKey: fallbackUserDefaultKey)
    }

    public func deleteApiKey() {
        deleteFromKeychain()
        UserDefaults.standard.removeObject(forKey: fallbackUserDefaultKey)
    }

    // MARK: - Model & Voice Options
    public var currentModel: String {
        Defaults[.conversationModelName]
    }

    public var currentVoice: String {
        Defaults[.conversationVoiceName]
    }

    public var systemInstruction: String {
        Defaults[.conversationSystemPrompt]
    }

    // MARK: - Keychain Helpers
    private func saveToKeychain(_ value: String) {
        deleteFromKeychain()
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
