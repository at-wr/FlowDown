//
//  MemoryType.swift
//  MemoryKit
//
//  Created by Alan Ye on 7/25/25.
//

import Foundation

public enum MemoryType: String, Codable, CaseIterable {
    case factual = "fact"
    case conversational = "conv"
    case procedural = "proc"
    
    public var displayName: String {
        switch self {
        case .factual:
            return "Factual"
        case .conversational:
            return "Conversational"
        case .procedural:
            return "Procedural"
        }
    }
    
    public var description: String {
        switch self {
        case .factual:
            return "User facts, preferences, and personal information"
        case .conversational:
            return "Cross-conversation discussion patterns and conclusions"
        case .procedural:
            return "User workflows, habits, and problem-solving approaches"
        }
    }
    
    public var defaultImportance: Float {
        switch self {
        case .factual:
            return 0.9
        case .conversational:
            return 0.7
        case .procedural:
            return 0.8
        }
    }
}