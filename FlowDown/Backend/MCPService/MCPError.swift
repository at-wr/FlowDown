//
//  MCPError.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Foundation

enum MCPError: Swift.Error, LocalizedError, Equatable {
    case serverDisabled
    case connectionFailed
    case capabilityNotSupported
    case samplingDenied
    case noViewController
    case noModelAvailable
    case elicitationDenied
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .serverDisabled:
            String(localized: "The server is currently disabled.")
        case .invalidConfiguration:
            String(localized: "Invalid configuration.")
        case .connectionFailed:
            String(localized: "Unable to connect to the MCP server. Please check your network or server status.")
        case .capabilityNotSupported:
            String(localized: "The MCP server does not support required capability.")
        case .samplingDenied:
            String(localized: "Sampling request was denied by the user.")
        case .noViewController:
            String(localized: "Unable to present the user interface at this time.")
        case .noModelAvailable:
            String(localized: "No AI model is currently available for sampling.")
        case .elicitationDenied:
            String(localized: "Elicitation request was denied by the user.")
        }
    }
}
