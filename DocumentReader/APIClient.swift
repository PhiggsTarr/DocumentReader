//
//  APIClient.swift
//  DocumentReader
//

import Foundation

final class APIClient {

    private let session: URLSession
    private let baseURL: URL

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60   // time to first byte
        config.timeoutIntervalForResource = 120 // entire transfer
        self.session = URLSession(configuration: config)

        let baseString = AppConfig.apiBaseURL

        guard let url = URL(string: baseString),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil
        else {
            // Fail loudly in debug; in release you may want a softer fallback
            self.baseURL = URL(string: "https://example.invalid")!
            return
        }

        self.baseURL = url
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: - Wire Models

    struct ChatWireMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    private struct AnalyzeRequest: Codable {
        let text: String
        let detail_level: String
    }

    private struct ChatRequest: Codable {
        let document_text: String?    // optional now
        let detail_level: String?
        let messages: [ChatWireMessage]
    }


    struct ChatResponse: Codable, Equatable {
        let reply: String
        let pdfDraft: PDFDraft?
        let limitations: [String]?

        enum CodingKeys: String, CodingKey {
            case reply
            case pdfDraft = "pdf_draft"
            case limitations
        }
    }

    // MARK: - Public API

    func analyzeDocument(text: String) async throws -> DocumentAnalyzeResponse {
        let url = try endpointURL("/analyze/document")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AnalyzeRequest(text: text, detail_level: "medium")
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await session.data(for: req)
        try validateHTTP(resp: resp, data: data, url: url)

        do {
            return try decoder.decode(DocumentAnalyzeResponse.self, from: data)
        } catch {
            throw APIError.decodeFailed(
                raw: String(data: data, encoding: .utf8) ?? "(non-utf8)",
                underlying: error
            )
        }
    }

    func chatAboutDocument(documentText: String, messages: [ChatWireMessage]) async throws -> ChatResponse {
        let url = try endpointURL("/chat/document")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let safeMessages = Array(messages.suffix(20))
        let payload = ChatRequest(document_text: documentText, detail_level: "medium", messages: safeMessages)

        req.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await session.data(for: req)
        try validateHTTP(resp: resp, data: data, url: url)

        do {
            return try decoder.decode(ChatResponse.self, from: data)
        } catch {
            throw APIError.decodeFailed(
                raw: String(data: data, encoding: .utf8) ?? "(non-utf8)",
                underlying: error
            )
        }
    }

    // MARK: - URL Building

    /// Build endpoint URLs safely and consistently.
    /// Pass paths like "/analyze/document" or "/chat/document".
    private func endpointURL(_ path: String) throws -> URL {
        guard baseURL.host != nil else {
            throw APIError.invalidBaseURL(AppConfig.apiBaseURL)
        }

        let cleanPath: String = {
            if path.hasPrefix("/") { return path }
            return "/" + path
        }()

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if components == nil { throw APIError.invalidBaseURL(AppConfig.apiBaseURL) }

        // Ensure we keep any existing base path, then append our endpoint.
        let existing = components?.path ?? ""
        let combined: String

        if existing.isEmpty || existing == "/" {
            combined = cleanPath
        } else {
            // Example: base has "/api" then endpoint "/analyze/document" => "/api/analyze/document"
            combined = existing + cleanPath
        }

        components?.path = combined
        guard let url = components?.url else {
            throw APIError.invalidURL("Could not build URL from base=\(baseURL) path=\(path)")
        }
        return url
    }

    // MARK: - Validation

    private func validateHTTP(resp: URLResponse, data: Data, url: URL) throws {
        guard let http = resp as? HTTPURLResponse else { return }

        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"

            // This is the smoking gun when you accidentally hit a website (HTML)
            throw APIError.http(status: http.statusCode,
                                raw: """
                                URL: \(url.absoluteString)

                                Response:
                                \(raw)
                                """)
        }

        // Optional: detect HTML even when status is 200 (misconfigured proxy)
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            throw APIError.http(status: http.statusCode,
                                raw: """
                                URL: \(url.absoluteString)

                                Got text/html, expected application/json.

                                Response:
                                \(raw)
                                """)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidBaseURL(String)
    case invalidURL(String)
    case http(status: Int, raw: String)
    case decodeFailed(raw: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let s):
            return "Invalid API base URL: \(s)"
        case .invalidURL(let s):
            return "Invalid request URL: \(s)"
        case .http(let status, let raw):
            return "Server error (HTTP \(status)).\n\n\(raw)"
        case .decodeFailed(let raw, let underlying):
            return """
            Could not decode the server response.

            Underlying:
            \(underlying.localizedDescription)

            Raw:
            \(raw)
            """
        }
    }
}
