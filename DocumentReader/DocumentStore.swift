//
//  DocumentStore.swift
//  DocumentReader
//
//  Saves a StoredDocument (text/hash/file metadata) + a related StoredAnalysis (analysis JSON + export)
//  Adds backwards-compatible decoding for legacy saved analyses.
//  Created by Gboinyee Tarr on 1/13/26.
//

import Foundation
import CoreData
import CryptoKit
import SwiftUI

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
        doc.fileURL = fileURL?.absoluteString

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
    ///
    /// Backwards-compatible:
    /// - New payloads (snake_case + CodingKeys) decode normally
    /// - Old payloads (camelCase / older encoding) are tried via a legacy decoder
    /// - If legacy succeeds, we migrate `analysisJSON` in place so future loads are fast/consistent
    func decodeAnalysis(_ storedAnalysis: StoredAnalysis) -> DocumentAnalyzeResponse? {
        guard let data = storedAnalysis.analysisJSON, !data.isEmpty else {
            print("❌ decodeAnalysis: analysisJSON missing/empty")
            return nil
        }

        // Try modern decode first
        if let modern = decodeModernDocumentAnalyzeResponse(data) {
            // Heuristic: if decode "succeeds" but the object is mostly empty, treat it as a legacy payload
            let looksEmpty =
                (modern.docType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
                (modern.summaryPlain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
                (modern.partyAnalysis?.isEmpty ?? true) &&
                (modern.analysisParagraphs?.isEmpty ?? true)

            if looksEmpty, let legacy = decodeLegacyDocumentAnalyzeResponse(data) {
                migrateStoredAnalysisJSONIfNeeded(storedAnalysis, analysis: legacy)
                return legacy
            }

            return modern
        }

        // Fallback to legacy decode
        if let legacy = decodeLegacyDocumentAnalyzeResponse(data) {
            migrateStoredAnalysisJSONIfNeeded(storedAnalysis, analysis: legacy)
            return legacy
        }

        return nil
    }

    /// Convenience: get the "latest" analysis for a given StoredDocument and decode it.
    func decodeLatestAnalysis(for document: StoredDocument) -> DocumentAnalyzeResponse? {
        guard let analyses = document.analyses as? Set<StoredAnalysis>, !analyses.isEmpty else {
            return nil
        }
        let latest = analyses
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .first
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

    // MARK: - Decoding helpers (modern + legacy)

    /// Modern decode path: your current model decoding expectations.
    private func decodeModernDocumentAnalyzeResponse(_ data: Data) -> DocumentAnalyzeResponse? {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(DocumentAnalyzeResponse.self, from: data)
        } catch {
            print("❌ decodeAnalysis modern failed:", error)
            return nil
        }
    }

    /// Legacy decode path: handles older saved JSON that was encoded with different key conventions.
    ///
    /// NOTE:
    /// If your old saved payload used camelCase keys (docType, summaryPlain, partyAnalysis, etc.),
    /// this decoder often succeeds where the modern one yields an "empty" object.
    private func decodeLegacyDocumentAnalyzeResponse(_ data: Data) -> DocumentAnalyzeResponse? {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            return try decoder.decode(DocumentAnalyzeResponse.self, from: data)
        } catch {
            print("❌ decodeAnalysis legacy failed:", error)
            return nil
        }
    }

    /// Migrates stored JSON to the latest encoding format.
    private func migrateStoredAnalysisJSONIfNeeded(_ stored: StoredAnalysis, analysis: DocumentAnalyzeResponse) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let newData = try encoder.encode(analysis)

            // Only write if it actually changed (avoid needless saves)
            if stored.analysisJSON != newData {
                stored.analysisJSON = newData
                try moc.save()
                print("✅ Migrated legacy saved analysisJSON to latest format")
            }
        } catch {
            print("❌ migrateStoredAnalysisJSONIfNeeded failed:", error)
        }
    }

    // MARK: - Helpers

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
