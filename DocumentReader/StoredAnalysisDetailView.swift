//
//  StoredAnalysisDetailView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/14/26.
//


import SwiftUI
import UIKit

struct StoredAnalysisDetailView: View {
    let stored: StoredAnalysis
    let documentText: String

    @State private var decoded: DocumentAnalyzeResponse?
    @State private var copiedToast: String?

    private let store = DocumentStore()

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {

                    // ✅ Chat card at the top (talk about THIS saved document)
                    Card("Chat") {
                        NavigationLink {
                            ChatView(
                                documentText: documentText,
                                suggestedQuestions: decoded?.suggestedQuestions ?? []
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("Chat about this saved document")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .disabled(documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // ✅ FULL analysis UI (reuse your existing AnalysisResultView)
                    if let decoded {
                        AnalysisResultView(
                            result: decoded,
                            documentText: documentText,
                            canSave: false // saved screen shouldn't show "Save"
                        )
                        // Optional: if you want it visually “read-only”, keep interactions.
                        // .disabled(false)
                    } else {
                        Card("Saved analysis") {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading saved analysis…")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }


                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Saved analysis")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
        .task {
            // Decode once when the view loads
            decoded = store.decodeAnalysis(stored)
        }
        .overlay(alignment: .top) {
            if let t = copiedToast {
                Text(t)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { copiedToast = nil }
                        }
                    }
            }
        }
    }

    private func toast(_ msg: String) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedToast = msg
        }
    }

    // Build export text in the SAME way AnalysisResultView does (reuse your logic)
    private func exportText(for result: DocumentAnalyzeResponse) -> String {
        var parts: [String] = []
        parts.append("Document type: \(result.docType ?? "Unknown")")
        if let c = result.confidence { parts.append("Confidence: \(String(format: "%.2f", c))") }
        parts.append("")

        if let wb = result.whoBenefitsMost {
            parts.append("Who benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
            if !wb.reasons.isEmpty {
                parts.append("Reasons:")
                parts.append(contentsOf: wb.reasons.map { "- \($0)" })
            }
            parts.append("")
        }

        parts.append("Summary:")
        parts.append(result.summaryPlain ?? "(none)")
        parts.append("")

        if let simple = result.simpleEnglish, !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Explain it to me in plain simple English:")
            parts.append(simple)
            parts.append("")
        }

        if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
            parts.append("Explain it to me like I'm 5:")
            parts.append(eli5[0])
            parts.append("")
            parts.append(eli5[1])
            parts.append("")
        }

        if let analogy = result.eli5Analogy, !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("ELI5 Analogy:")
            parts.append(analogy)
            parts.append("")
        }

        if let parties = result.partyAnalysis, !parties.isEmpty {
            parts.append("Benefits, liabilities, possible penalties, and catches by party:")
            for p in parties {
                parts.append("\n\(p.party):")

                if !p.benefits.isEmpty {
                    parts.append("  Benefits:")
                    parts.append(contentsOf: p.benefits.map { "  - \($0)" })
                }

                if !p.liabilities.isEmpty {
                    parts.append("  Liabilities / obligations:")
                    parts.append(contentsOf: p.liabilities.map { "  - \($0)" })
                }

                if !p.possiblePenalties.isEmpty {
                    parts.append("  Possible penalties / consequences:")
                    parts.append(contentsOf: p.possiblePenalties.map { "  - \($0)" })
                }

                if !p.catches.isEmpty {
                    parts.append("  Catches / gotchas:")
                    parts.append(contentsOf: p.catches.map { "  - \($0)" })
                }

                if !p.rights.isEmpty {
                    parts.append("  Rights:")
                    for r in p.rights {
                        parts.append("  - \(r.right): \(r.details)")
                    }
                }
            }
            parts.append("")
        }

        if let paras = result.analysisParagraphs, !paras.isEmpty {
            parts.append("Detailed analysis:")
            parts.append(contentsOf: paras.map { "- \($0)" })
            parts.append("")
        }

        if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
            parts.append("Drafts:")
            for d in drafts {
                parts.append("\n\(d.title):\n\(d.text)\n")
            }
        }

        if let lim = result.limitations, !lim.isEmpty {
            parts.append("\nLimitations:")
            parts.append(contentsOf: lim.map { "- \($0)" })
        }

        return parts.joined(separator: "\n")
    }
}
