//
//  StoredDocumentDetailView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/14/26.
//


import SwiftUI

struct StoredDocumentDetailView: View {
    let document: StoredDocument
    @State private var analyses: [StoredAnalysis] = []

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    documentCard
                    savedAnalysesCard
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
        .task {
            let set = (document.analyses as? Set<StoredAnalysis>) ?? []
            analyses = set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        }
    }

    private var documentCard: some View {
        Card("Document") {
            VStack(alignment: .leading, spacing: 8) {
                Text(document.title ?? "Untitled")
                    .font(.title3.weight(.bold))

                if let docType = document.docType {
                    Text(docType)
                        .foregroundStyle(.secondary)
                }

                if let text = document.documentText, !text.isEmpty {
                    Divider().opacity(0.25)
                    Text(text)
                        .foregroundStyle(.secondary)
                        .lineLimit(10)
                }
            }
        }
    }

    private var savedAnalysesCard: some View {
        Card("Saved analyses") {
            VStack(alignment: .leading, spacing: 10) {
                if analyses.isEmpty {
                    Text("No saved analyses yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(analyses) { a in
                        NavigationLink {
                            // ✅ PASS document text so the Chat card in SavedAnalysisDetailView works
                            StoredAnalysisDetailView(
                                stored: a,
                                documentText: document.documentText ?? ""
                            )
                        } label: {
                            analysisRow(a)
                        }

                        Divider().opacity(0.25)
                    }
                }
            }
        }
    }

    private func analysisRow(_ a: StoredAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(a.docType ?? "Analysis")
                .font(.headline.weight(.semibold))

            HStack {
                if a.confidence > 0 {
                    Text("Confidence: \(Int(a.confidence * 100))%")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text((a.createdAt ?? Date()), style: .date)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
