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

    private var latestAnalysis: StoredAnalysis? { analyses.first }

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
        .task(id: document.objectID) {
            reloadAnalyses()
        }
        .onAppear {
            reloadAnalyses()
        }
    }

    private func reloadAnalyses() {
        let set = (document.analyses as? Set<StoredAnalysis>) ?? []
        analyses = set.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    private var documentCard: some View {
        Card("Document") {
            VStack(alignment: .leading, spacing: 10) {
                Text(document.title ?? "Untitled")
                    .font(.title3.weight(.bold))

                if let docType = document.docType, !docType.isEmpty {
                    Text(docType)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.25)

                if let a = latestAnalysis {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary (from latest saved analysis)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        let summary = (a.summaryPlain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(summary.isEmpty ? "No summary saved for this analysis." : summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(10)

                        HStack(spacing: 10) {
                            if let date = a.createdAt {
                                Text("Last analyzed: \(date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if a.confidence > 0 {
                                Text("Confidence: \(Int(a.confidence * 100))%")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("No saved analysis yet. Run an analysis to see a summary here.")
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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
                            StoredAnalysisDetailView(
                                stored: a
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
