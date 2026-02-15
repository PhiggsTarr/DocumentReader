//
//  DocumentStore.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/13/26.
//

import Foundation
import CoreData
import CryptoKit
import SwiftUI
import VisionKit
import UniformTypeIdentifiers

// MARK: - Model

struct ImportedDocument: Identifiable {
    let id = UUID()
    let displayName: String
    let localURL: URL
    let kind: Kind
    
    enum Kind {
        case pdf
        case image
        case file
    }
}
//
//  DocumentStore.swift
//  DocumentReader
//
//  Saves a StoredDocument (text/hash/file metadata) + a related StoredAnalysis (analysis JSON + export)
//  so your Core Data model matches your screenshots.
//
//  Created by Gboinyee Tarr on 1/13/26.
//

import Foundation
import CoreData
import CryptoKit

@MainActor
final class DocumentStore: ObservableObject {

    private var moc: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    // MARK: - Public API

    /// Save a document + its analysis.
    /// - Important: This saves `documentText/textHash/fileURL/title` into **StoredDocument**
    ///              and saves `analysisJSON/exportText/summary/etc` into **StoredAnalysis**
    ///              then links: analysis.document = doc
    func saveDocument(
        title: String,
        documentText: String,
        fileURL: URL?,                 // optional so nil works
        analysis: DocumentAnalyzeResponse,
        exportText: String
    ) throws {
        let hash = sha256(documentText)

        // 1) If doc already exists, bail (prevents duplicates)
        if let _ = try existsDocument(withTextHash: hash) {
            return
        }

        // 2) Create the document (StoredDocument holds the text + hash)
        let doc = StoredDocument(context: moc)
        doc.id = UUID()
        doc.createdAt = Date()
        doc.lastOpenedAt = Date()
        doc.title = title
        doc.docType = analysis.docType ?? "Document"
        doc.documentText = documentText
        doc.textHash = hash
        doc.fileURL = fileURL?.absoluteString   // <-- your model shows `fileURL` on StoredDocument (String)

        // 3) Create the analysis (StoredAnalysis holds analysis JSON + export)
        let a = StoredAnalysis(context: moc)
        a.id = UUID()
        a.createdAt = Date()
        a.title = title
        a.docType = analysis.docType ?? "Document"
        a.confidence = analysis.confidence ?? 0
        a.summaryPlain = analysis.summaryPlain ?? ""

        // Optional “who benefits most” fields shown in your model
        a.whoBenefitsMostParty = analysis.whoBenefitsMost?.party ?? ""
        a.whoBenefitsMostConfidence = analysis.whoBenefitsMost?.confidence ?? 0

        a.exportText = exportText

        // Your StoredAnalysis model shows `fileURLString` (String)
        a.fileURLString = fileURL?.absoluteString

        // Encode the full response to Binary Data (analysisJSON)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        a.analysisJSON = try encoder.encode(analysis)

        // 4) Link them (your inverse should populate doc.analyses if configured)
        a.document = doc

        try moc.save()
    }

    /// Returns the existing StoredDocument (if any) for a document hash.
    func existsDocument(withTextHash hash: String) throws -> StoredDocument? {
        let req = StoredDocument.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "textHash == %@", hash)

        let results = try moc.fetch(req)
        return results.first
    }

    /// Decode the saved JSON from a StoredAnalysis back into `DocumentAnalyzeResponse`.
    func decodeAnalysis(_ storedAnalysis: StoredAnalysis) -> DocumentAnalyzeResponse? {
        guard let data = storedAnalysis.analysisJSON else { return nil }
        return decodeDocumentAnalyzeResponse(from: data)
    }

    /// Convenience: get the "latest" analysis for a given StoredDocument and decode it.
    func decodeLatestAnalysis(for document: StoredDocument) -> DocumentAnalyzeResponse? {
        guard let analyses = document.analyses as? Set<StoredAnalysis>, !analyses.isEmpty else {
            return nil
        }
        let latest = analyses.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.first
        guard let a = latest else { return nil }
        return decodeAnalysis(a)
    }

    /// Fetch all saved documents (newest first).
    func fetchSavedDocuments(limit: Int = 100) throws -> [StoredDocument] {
        let req = StoredDocument.fetchRequest()
        req.fetchLimit = limit
        req.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        return try moc.fetch(req)
    }

    /// Fetch analyses for a document (newest first).
    func fetchAnalyses(for document: StoredDocument, limit: Int = 50) throws -> [StoredAnalysis] {
        let req = StoredAnalysis.fetchRequest()
        req.fetchLimit = limit
        req.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        req.predicate = NSPredicate(format: "document == %@", document)
        return try moc.fetch(req)
    }

    // MARK: - Helpers

    private func decodeDocumentAnalyzeResponse(from data: Data) -> DocumentAnalyzeResponse? {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(DocumentAnalyzeResponse.self, from: data)
        } catch {
            print("❌ decodeAnalysis failed:", error)
            return nil
        }
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
