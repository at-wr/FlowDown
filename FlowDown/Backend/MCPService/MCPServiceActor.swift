//  MCPServiceActor.swift
//  FlowDown
//
//  Created by Copilot on 2024/7/11.
//

import Foundation

actor MCPServiceActor {
    static let shared = MCPServiceActor()

    private init() {}

    func run<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await operation()
    }

    func run<T>(_ operation: @Sendable @escaping () async -> T) async -> T {
        await operation()
    }
}
