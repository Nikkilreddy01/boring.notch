//
//  CaptionManager.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Combine
import Foundation

public struct TurnItem: Identifiable, Equatable {
    public let id = UUID()
    public let role: Role
    public var text: String
    public let timestamp: Date = Date()

    public enum Role {
        case user
        case assistant
    }
}

@MainActor
public final class CaptionManager: ObservableObject {
    public static let shared = CaptionManager()

    @Published public var currentUserText: String = ""
    @Published public var currentAIText: String = ""
    @Published public var turnsHistory: [TurnItem] = []

    private init() {}

    private func sanitizeText(_ text: String) -> String {
        var result = text
        // Strip XML / bracket tags like <no speech>, {pause}, [laughter], etc.
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\{[^\\}]+\\}", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\[[^\\]]+\\]", with: "", options: .regularExpression)
        return result
    }

    public func appendAIText(_ chunk: String) {
        let cleaned = sanitizeText(chunk)
        guard !cleaned.isEmpty else { return }
        currentAIText += cleaned
    }

    public func setUserText(_ text: String) {
        currentUserText = sanitizeText(text)
    }

    public func commitTurn() {
        let cleanUser = currentUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAI = currentAIText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanUser.isEmpty {
            turnsHistory.append(TurnItem(role: .user, text: cleanUser))
        }
        if !cleanAI.isEmpty {
            turnsHistory.append(TurnItem(role: .assistant, text: cleanAI))
        }

        // Keep last 15 items in history
        if turnsHistory.count > 15 {
            turnsHistory.removeFirst(turnsHistory.count - 15)
        }

        currentUserText = ""
        currentAIText = ""
    }

    public func clear() {
        currentUserText = ""
        currentAIText = ""
        turnsHistory.removeAll()
    }
}
