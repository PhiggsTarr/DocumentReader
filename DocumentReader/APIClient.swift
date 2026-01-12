import Foundation

final class APIClient {
    private let baseURL = URL(string: "https://debt-letter-api.documentreader.workers.dev")!

    struct ChatWireMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    private struct AnalyzeRequest: Codable { let text: String }

    private struct ChatRequest: Codable {
        let document_text: String
        let messages: [ChatWireMessage]
    }

    // ✅ NEW: Decode reply + optional pdf draft
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

    func analyzeDocument(text: String) async throws -> DocumentAnalyzeResponse {
        let url = baseURL.appendingPathComponent("analyze/document")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AnalyzeRequest(text: text))

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.validateHTTP(resp: resp, data: data)

        do {
            return try Self.jsonDecoder.decode(DocumentAnalyzeResponse.self, from: data)
        } catch {
            throw APIError.decodeFailed(raw: String(data: data, encoding: .utf8) ?? "(non-utf8)", underlying: error)
        }
    }

    // ✅ NEW: chat returns ChatResponse (reply + optional pdf draft)
    func chatAboutDocument(documentText: String, messages: [ChatWireMessage]) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("chat/document")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let safeMessages = messages.suffix(20)
        req.httpBody = try JSONEncoder().encode(ChatRequest(document_text: documentText, messages: Array(safeMessages)))

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.validateHTTP(resp: resp, data: data)

        do {
            return try Self.jsonDecoder.decode(ChatResponse.self, from: data)
        } catch {
            throw APIError.decodeFailed(raw: String(data: data, encoding: .utf8) ?? "(non-utf8)", underlying: error)
        }
    }

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static func validateHTTP(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, raw: raw)
        }
    }
}

enum APIError: LocalizedError {
    case http(status: Int, raw: String)
    case decodeFailed(raw: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .http(status, raw):
            return "Server error (\(status)). \(raw)"
        case let .decodeFailed(raw, underlying):
            return "Could not decode the server response. \(raw)\n\nUnderlying: \(underlying.localizedDescription)"
        }
    }
}
