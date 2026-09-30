//
//  RealtimeAIProvider.swift
//  boringNotch
//
//  Created by Antigravity on 2026-09-29.
//

import Foundation

public protocol RealtimeAIProviderDelegate: AnyObject {
    func providerDidConnect(_ provider: any RealtimeAIProvider)
    func providerDidDisconnect(_ provider: any RealtimeAIProvider, error: Error?)
    func provider(_ provider: any RealtimeAIProvider, didReceiveServerAudio data: Data)
    func provider(_ provider: any RealtimeAIProvider, didReceiveServerText text: String)
    func provider(_ provider: any RealtimeAIProvider, didDetectInterruption: Bool)
    func providerDidCompleteTurn(_ provider: any RealtimeAIProvider)
    func provider(_ provider: any RealtimeAIProvider, didEncounterError message: String)
}

public protocol RealtimeAIProvider: AnyObject {
    var delegate: RealtimeAIProviderDelegate? { get set }
    var isConnected: Bool { get }
    func connect() async throws
    func disconnect()
    func sendAudioChunk(_ data: Data)
    func sendTextMessage(_ text: String)
}
