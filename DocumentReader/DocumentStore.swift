//
//  DocumentStore.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/13/26.
//

import Foundation
import CoreData
import CryptoKit

@MainActor
final class DocumentStore: ObservableObject {
    private let container: NSPersistentContainer

    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }

    // MARK: - Save (single analysis helper)

    /// Saves an analysis result into Core Data under a StoredDocument.
    @discardableResult
    func saveAnalysis(
        result: DocumentAnalyzeResponse,
        for document: StoredDocument,
        in context: NSManagedObjectContext
    ) throws -> StoredAnalysis {

        let a = StoredAnalysis(context: context)

        a.createdAt = Date()
        a.docType = result.docType
        a.confidence = result.confidence ?? 0

        // ✅ Store summary directly on StoredAnalysis (Option A)
        a.summaryPlain = result.summaryPlain

        // Link
        a.document = document

        try context.save()
        return a
    }

    // MARK: - Exists

    func existsDocument(withTextHash hash: String) throws -> StoredDocument? {
        let request = StoredDocument.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "textHash == %@", hash)
        return try container.viewContext.fetch(request).first
    }

    func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Save a new document + analysis

    func saveDocument(
        title: String?,
        documentText: String?,
        fileURL: URL?,
        analysis: DocumentAnalyzeResponse,
        exportText: String
    ) throws {
        let context = container.viewContext

        // Create document
        let doc = StoredDocument(context: context)
        doc.id = UUID()
        doc.title = title
        doc.createdAt = Date()
        doc.lastOpenedAt = Date()
        doc.documentText = documentText
        doc.fileURL = fileURL?.path
        doc.docType = analysis.docType
        doc.textHash = sha256(documentText ?? "")

        // Create analysis
        let stored = StoredAnalysis(context: context)
        stored.id = UUID()
        stored.createdAt = Date()
        stored.exportText = exportText
        stored.docType = analysis.docType
        stored.confidence = analysis.confidence ?? 0

        // ✅ FIX: this was missing, causing your summary to always be nil
        stored.summaryPlain = analysis.summaryPlain

        if let wb = analysis.whoBenefitsMost {
            stored.whoBenefitsMostParty = wb.party
            stored.whoBenefitsMostConfidence = wb.confidence
        }

        stored.analysisJSON = try JSONEncoder().encode(analysis)

        // Link
        stored.document = doc

        try context.save()
    }

    // MARK: - Add a new analysis run to an existing document

    func addAnalysis(
        to document: StoredDocument,
        analysis: DocumentAnalyzeResponse,
        exportText: String
    ) throws {
        let context = container.viewContext

        let stored = StoredAnalysis(context: context)
        stored.id = UUID()
        stored.createdAt = Date()
        stored.exportText = exportText
        stored.docType = analysis.docType
        stored.confidence = analysis.confidence ?? 0

        // ✅ Keep storing summary on every analysis row
        stored.summaryPlain = analysis.summaryPlain

        if let wb = analysis.whoBenefitsMost {
            stored.whoBenefitsMostParty = wb.party
            stored.whoBenefitsMostConfidence = wb.confidence
        }

        stored.analysisJSON = try JSONEncoder().encode(analysis)
        stored.document = document

        document.lastOpenedAt = Date()

        try context.save()
    }

    // MARK: - Fetch recent documents

    func fetchRecentDocuments(limit: Int = 50) throws -> [StoredDocument] {
        let request = StoredDocument.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \StoredDocument.lastOpenedAt, ascending: false)
        ]
        request.fetchLimit = limit

        return try container.viewContext.fetch(request) as? [StoredDocument] ?? []
    }

    // MARK: - Decode a StoredAnalysis back into DocumentAnalyzeResponse

    func decodeAnalysis(_ stored: StoredAnalysis) -> DocumentAnalyzeResponse? {
        guard let data = stored.analysisJSON else { return nil }
        return try? JSONDecoder().decode(DocumentAnalyzeResponse.self, from: data)
    }

    // MARK: - Delete a document (cascades to analyses)

    func deleteDocument(_ doc: StoredDocument) throws {
        let context = container.viewContext
        context.delete(doc)
        try context.save()
    }
}
