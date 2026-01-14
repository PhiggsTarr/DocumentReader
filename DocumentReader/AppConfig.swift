//
//  AppConfig.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/13/26.
//

import Foundation

enum AppConfig {

    /// Add this to Info.plist:
    /// API_BASE_URL = https://YOUR-WORKER-OR-DOMAIN (NO path, NO trailing slash)
    ///
    /// Examples:
    /// - https://documentreader-api.YOURNAME.workers.dev
    /// - https://api.yourdomain.com
    ///
    /// IMPORTANT:
    /// If this accidentally points to a normal website (like bedpage.com),
    /// you'll get HTML back and JSON decoding will fail.
    static var apiBaseURL: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // Don’t strip "https://" by accident — only remove trailing "/"
            if trimmed.isEmpty { return fallback }

            // Remove ONLY trailing slashes (not all "/" characters)
            var cleaned = trimmed
            while cleaned.hasSuffix("/") { cleaned.removeLast() }

            return cleaned
        }

        return fallback
    }

    /// Fallback (replace with your actual deployed worker URL)
    private static var fallback: String {
        // ⚠️ PUT YOUR REAL WORKER URL HERE
        return "https://YOUR-WORKER-SUBDOMAIN.YOUR-DOMAIN"
    }
}
