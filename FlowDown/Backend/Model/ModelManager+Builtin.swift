//
//  ModelManager+Builtin.swift
//  FlowDown
//
//  Created by 秋星桥 on 4/6/25.
//

import Foundation
import Storage

extension CloudModel {
    enum BuiltinModel: CaseIterable {
        case openai
        case openai_fast
        case mistral

        var model: CloudModel {
            switch self {
            case .openai:
                CloudModel(
                    id: "95b2ed31-d84d-4ce5-86a4-d362687bb18a",
                    model_identifier: "openai",
                    endpoint: "https://text.pollinations.ai/openai/v1/chat/completions",
                    context: .medium_64k,
                    capabilities: [.tool, .visual],
                    comment: String(localized: "This model is provided by pollinations.ai free of charge. Rate limit applies."),
                )

            case .openai_fast:
                CloudModel(
                    id: "95b2ed31-d84d-4ce5-86a4-d362687bb18a",
                    model_identifier: "openai-fast",
                    endpoint: "https://text.pollinations.ai/openai/v1/chat/completions",
                    context: .medium_64k,
                    capabilities: [.tool, .visual],
                    comment: String(localized: "This model is provided by pollinations.ai free of charge. Rate limit applies."),
                )

            case .mistral:
                CloudModel(
                    id: "a7f8e9d6-c5b4-4a3b-9f2e-1d8c7b6a5e4f",
                    model_identifier: "mistral",
                    endpoint: "https://text.pollinations.ai/openai/v1/chat/completions",
                    context: .medium_64k,
                    capabilities: [.tool, .visual],
                    comment: String(localized: "This model is provided by pollinations.ai free of charge. Rate limit applies."),
                )
            }
        }
    }
}
