//
//  ConversationId.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/17/26.
//

import Foundation
import CryptoKit

enum ConversationId {
    /// Deterministic ID based on the document text.
    /// Same text => same conversationId => same artifacts folder.
    static func fromDocumentText(_ text: String) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let data = Data(normalized.utf8)
        let digest = SHA256.hash(data: data)

        // hex string
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()

        // Keep it short but unique enough
        return "doc-\(hex.prefix(24))"
    }
}
