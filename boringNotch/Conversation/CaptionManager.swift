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

    public func appendAIText(_ chunk: String) {
        currentAIText += chunk
    }

    public func setUserText(_ text: String) {
        currentUserText = text
    }

    public func commitTurn() {
        if !currentUserText.isEmpty {
            turnsHistory.append(TurnItem(role: .user, text: currentUserText))
        }
        if !currentAIText.isEmpty {
            turnsHistory.append(TurnItem(role: .assistant, text: currentAIText))
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
