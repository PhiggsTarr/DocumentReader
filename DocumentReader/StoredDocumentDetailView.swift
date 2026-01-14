//
//  StoredDocumentDetailView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/14/26.
//


import SwiftUI

struct StoredDocumentDetailView: View {
    let document: StoredDocument

    var sortedAnalyses: [StoredAnalysis] {
        let set = (document.analyses as? Set<StoredAnalysis>) ?? []
        return set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {

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

                    Card("Saved analyses") {
                        VStack(alignment: .leading, spacing: 10) {
                            if sortedAnalyses.isEmpty {
                                Text("No saved analyses yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(sortedAnalyses) { a in
                                    NavigationLink {
                                        StoredAnalysisDetailView(analysis: a)
                                    } label: {
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

                                    Divider().opacity(0.25)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Document")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
    }
}
