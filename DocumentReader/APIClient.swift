//
//  APIClient.swift
//  DocumentReader
//

import Foundation
import Compression

final class APIClient {

    // MARK: - Config

    private let session: URLSession
    private let baseURL: URL

    /// Defaults:
    /// - analyze is "short" for speed
    /// - chat is "medium"
    private let defaultAnalyzeDetailLevel: DetailLevel = .medium
    private let defaultChatDetailLevel: DetailLevel = .medium

    /// Hard cap how much text we send over the wire.
    /// This is one of the biggest speed wins.
    private let maxAnalyzeChars: Int = 20_000

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true

        // Tweak these to your taste. Biggest pain is time-to-first-byte from your worker/OpenAI hop.
        config.timeoutIntervalForRequest = 120   // time to first byte
        config.timeoutIntervalForResource = 240  // entire transfer
        config.httpMaximumConnectionsPerHost = 6

        self.session = URLSession(configuration: config)

        let baseString = AppConfig.apiBaseURL

        guard let url = URL(string: baseString),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil
        else {
            self.baseURL = URL(string: "https://example.invalid")!
            return
        }

        self.baseURL = url
    }

    // MARK: - Decoder

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Worker returns snake_case fields (doc_type, summary_plain, etc).
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    
    private let chatDecoder: JSONDecoder = {
        let d = JSONDecoder()
        // Worker returns snake_case fields (doc_type, summary_plain, etc).
       // d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    // MARK: - Detail levels

    enum DetailLevel: String, Codable {
        case short
        case medium
        case long
    }

    // MARK: - Wire Models

    struct ChatWireMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    private struct AnalyzeRequest: Codable {
        let text: String
        let detail_level: DetailLevel
    }

    private struct ChatRequest: Codable {
        let document_text: String?
        let detail_level: DetailLevel?
        let messages: [ChatWireMessage]
    }

    struct ChatResponse: Decodable {
        let reply: String
        let pdfDraft: PDFDraft?
        let pdfAllowed: Bool?
        let limitations: [String]?
        let buildId: String?
        let openaiError: String?   // ✅ ADD THIS

        enum CodingKeys: String, CodingKey {
            case reply
            case pdfDraft = "pdf_draft"
            case pdfAllowed = "pdf_allowed"
            case limitations
            case buildId = "build_id"
            case openaiError = "openai_error"   // ✅ ADD THIS
        }
    }
    
    struct CreditsStatus: Decodable {
        let isPro: Bool?
        let remaining: Int?
    }

    struct PaywallRequiredResponse: Decodable {
        let error: String              // "paywall_required"
        let message: String?
        let credits: CreditsStatus?
    }



    // MARK: - Public API

    /// Fast by default. Pass detailLevel: .medium or .long when the user requests deep analysis.
    func analyzeDocument(text: String, detailLevel: DetailLevel? = nil) async throws -> DocumentAnalyzeResponse {
        let url = try endpointURL("/analyze/document")

        let compact = Self.compactForAnalysis(text, maxChars: maxAnalyzeChars)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let installId = InstallID.getOrCreate()
        req.setValue(installId, forHTTPHeaderField: "X-Install-Id")

        // Tell the server what this call costs.
        // short/medium = 1 scan; long(deep) = 2 scans (base + extra)
        let cost: Int = (detailLevel ?? defaultAnalyzeDetailLevel) == .long ? 2 : 1
        req.setValue(String(cost), forHTTPHeaderField: "X-Scan-Cost")

        let payload = AnalyzeRequest(
            text: compact,
            detail_level: detailLevel ?? defaultAnalyzeDetailLevel
        )

        req.httpBody = try JSONEncoder().encode(payload) // ✅ NO compression

        let (data, resp) = try await withRetry(maxAttempts: 3) {
            try await self.session.data(for: req)
        }

        try validateHTTP(resp: resp, data: data, url: url)
//#if DEBUG
if let raw = String(data: data, encoding: .utf8) {
    print("✅ /chat/document raw response:\n\(raw)")
    print("✅ /analyze/document raw response:\n\(raw)")
}
//#endif

        do {
            return try decoder.decode(DocumentAnalyzeResponse.self, from: data)
        } catch {
            throw APIError.decodeFailed(
                raw: String(data: data, encoding: .utf8) ?? "(non-utf8)",
                underlying: error
            )
        }
    }

    func chatAboutDocument(
        documentText: String,
        messages: [ChatWireMessage],
        detailLevel: DetailLevel? = nil
    ) async throws -> ChatResponse {
        let url = try endpointURL("/chat/document")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let safeMessages = Array(messages.suffix(20))
        let payload = ChatRequest(
            document_text: documentText,
            detail_level: detailLevel ?? defaultChatDetailLevel,
            messages: safeMessages
        )

        req.httpBody = try JSONEncoder().encode(payload) // ✅ NO compression

        let (data, resp) = try await withRetry(maxAttempts: 3) {
            try await self.session.data(for: req)
        }

        try validateHTTP(resp: resp, data: data, url: url)

        do {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            print("🧾 RAW /chat/document:\n\(raw)")
            let decoded = try chatDecoder.decode(ChatResponse.self, from: data)
            print("✅ decoded pdfAllowed:", decoded.pdfAllowed as Any)
            print("✅ decoded has pdfDraft:", decoded.pdfDraft != nil)
            print("✅ buildId:", decoded.buildId as Any)
            print("✅ openaiError:", decoded.openaiError as Any)
            return decoded
        } catch {
            throw APIError.decodeFailed(
                raw: String(data: data, encoding: .utf8) ?? "(non-utf8)",
                underlying: error
            )
        }
    }

    // MARK: - URL Building

    private func endpointURL(_ path: String) throws -> URL {
        guard baseURL.host != nil else {
            throw APIError.invalidBaseURL(AppConfig.apiBaseURL)
        }

        let cleanPath: String = {
            if path.hasPrefix("/") { return path }
            return "/" + path
        }()

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        guard components != nil else { throw APIError.invalidBaseURL(AppConfig.apiBaseURL) }

        let existing = components?.path ?? ""
        let combined: String

        if existing.isEmpty || existing == "/" {
            combined = cleanPath
        } else {
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

        if http.statusCode == 402 {
            // Worker returns JSON explaining paywall
            if let decoded = try? decoder.decode(PaywallRequiredResponse.self, from: data) {
                throw APIError.paywallRequired(
                    message: decoded.message ?? "You’re out of scans. Please upgrade to continue.",
                    remaining: decoded.credits?.remaining
                )
            } else {
                let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                throw APIError.paywallRequired(message: raw, remaining: nil)
            }
        }

        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            throw APIError.http(status: http.statusCode, raw: "URL: \(url.absoluteString)\n\nResponse:\n\(raw)")
        }

        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("text/html") {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            throw APIError.http(status: http.statusCode, raw: "URL: \(url.absoluteString)\n\nGot text/html.\n\nResponse:\n\(raw)")
        }
    }

    // MARK: - Retry

    private func withRetry<T>(
        maxAttempts: Int,
        baseDelaySeconds: Double = 0.6,
        task: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0

        while true {
            attempt += 1
            do {
                return try await task()
            } catch {
                if attempt >= maxAttempts || !Self.isTransient(error) {
                    throw error
                }

                let delay = baseDelaySeconds * pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.25)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        let ns = error as NSError

        if ns.domain == NSURLErrorDomain {
            let transientCodes: Set<Int> = [
                NSURLErrorTimedOut,                 // -1001
                NSURLErrorNetworkConnectionLost,    // -1005
                NSURLErrorNotConnectedToInternet,   // -1009
                NSURLErrorCannotFindHost,           // -1003
                NSURLErrorCannotConnectToHost,      // -1004
                NSURLErrorDNSLookupFailed           // -1006
            ]
            if transientCodes.contains(ns.code) { return true }
        }

        if let apiErr = error as? APIError, case .http(let status, _) = apiErr {
            if (500...599).contains(status) { return true }
        }

        return false
    }

    // MARK: - Text compaction

    /// Reduces huge OCR dumps to the most informative parts so analysis is faster and less likely to time out.
    private static func compactForAnalysis(_ text: String, maxChars: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxChars else { return t }

        let lines = t.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let keywords = [
            "termination", "arbitration", "governing law", "jurisdiction",
            "fees", "penalty", "interest", "default", "cure", "notice",
            "indemn", "liability", "warranty", "attorney", "venue",
            "confidential", "noncompete", "non-compete", "assignment"
        ]

        let keyLines = lines.filter { line in
            let l = line.lowercased()
            return keywords.contains { l.contains($0) }
        }

        let head = String(t.prefix(2500))
        let tail = String(t.suffix(2500))
        let middle = keyLines.joined(separator: "\n")

        let stitched = ([head, middle, tail].filter { !$0.isEmpty }).joined(separator: "\n\n---\n\n")
        return String(stitched.prefix(maxChars))
    }
}

// MARK: - Compression helper

private enum CompressionError: LocalizedError {
    case encodeFailed
    var errorDescription: String? { "Could not compress request body." }
}

private extension Data {
    /// Zlib-compress (fast). Many servers accept this even when you set Content-Encoding: gzip,
    /// but strictly speaking gzip framing != zlib framing.
    func zlibCompressed() throws -> Data {
        guard !isEmpty else { return self }

        // ✅ Use Swift.max to avoid the "max refers to instance method" compiler error
        let dstCapacity = Swift.max(64 * 1024, count / 2)
        var dst = Data(count: dstCapacity)

        // ✅ Capture counts BEFORE withUnsafeMutableBytes to avoid overlapping access
        let dstSize = dst.count
        let srcSize = self.count

        let compressedSize: Int = dst.withUnsafeMutableBytes { dstPtr in
            guard let dstBase = dstPtr.baseAddress else { return 0 }

            return self.withUnsafeBytes { srcPtr in
                guard let srcBase = srcPtr.baseAddress else { return 0 }

                return compression_encode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    srcBase.assumingMemoryBound(to: UInt8.self),
                    srcSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard compressedSize > 0 else { throw CompressionError.encodeFailed }
        dst.count = compressedSize
        return dst
    }
}


// MARK: - Errors

enum APIError: LocalizedError {
    case invalidBaseURL(String)
    case invalidURL(String)
    case http(status: Int, raw: String)
    case decodeFailed(raw: String, underlying: Error)
    case paywallRequired(message: String, remaining: Int?)

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
        case .paywallRequired(message: let message, remaining: let remaining):
            if let r = remaining {
                return "\(message)\n\nScans remaining: \(r)"
            }
            return message
        }
    }
}
