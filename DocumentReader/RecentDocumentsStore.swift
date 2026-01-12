//
//  RecentDocumentsStore.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/11/26.
//


import Foundation

struct RecentDocument: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let snippet: String
    let fullText: String
    let docType: String?
    let createdAt: Date
}

@MainActor
final class RecentDocumentsStore: ObservableObject {
    @Published private(set) var items: [RecentDocument] = []

    private let key = "recent_documents_v1"
    private let maxItems = 12

    init() {
        load()
    }

    func add(fullText: String, analysis: DocumentAnalyzeResponse?) {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return }

        let docType = analysis?.docType
        let title = docType ?? "Legal Document"
        let snippet = String(trimmed.prefix(140))

        let newItem = RecentDocument(
            id: UUID(),
            title: title,
            snippet: snippet,
            fullText: trimmed,
            docType: docType,
            createdAt: Date()
        )

        items.removeAll { $0.snippet == newItem.snippet } // naive de-dupe
        items.insert(newItem, at: 0)
        items = Array(items.prefix(maxItems))
        save()
    }

    func remove(_ item: RecentDocument) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            items = try JSONDecoder().decode([RecentDocument].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // ignore
        }
    }
}
