import SwiftUI
import UIKit

struct AnalysisResultView: View {
    let result: DocumentAnalyzeResponse
    let documentText: String

    @State private var copiedToast: String?

    private var exportText: String {
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
            parts.append("Explanation in simple English:")
            parts.append(simple)
            parts.append("")
        }

        if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
            parts.append("Explain like I'm 5:")
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

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {

                    Card("Summary") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(result.summaryPlain ?? "No summary returned.")
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let wb = result.whoBenefitsMost {
                                Divider().opacity(0.25)
                                Text("Likely benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let paras = result.analysisParagraphs, !paras.isEmpty {
                        Card("Detailed analysis") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(paras.indices, id: \.self) { i in
                                    Text(paras[i])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if i != paras.count - 1 { Divider().opacity(0.25) }
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let simple = result.simpleEnglish,
                       !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Card("Explanation in simple English") {
                            Text(simple)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ✅ NEW: ELI5 section
                    if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
                        Card("Explain like I’m 5") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(eli5[0])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Divider().opacity(0.25)

                                Text(eli5[1])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let analogy = result.eli5Analogy,
                                   !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Divider().opacity(0.25)
                                    Text("Analogy")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(analogy)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    if let parties = result.partyAnalysis, !parties.isEmpty {
                        Card("Benefits, liabilities, penalties & catches") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(parties) { p in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(p.party)
                                            .font(.headline)

                                        if !p.benefits.isEmpty {
                                            sectionTitle("Benefits")
                                            bulletList(p.benefits)
                                        }

                                        if !p.liabilities.isEmpty {
                                            sectionTitle("Liabilities / obligations")
                                            bulletList(p.liabilities)
                                        }

                                        if !p.possiblePenalties.isEmpty {
                                            sectionTitle("Possible penalties / consequences")
                                            bulletList(p.possiblePenalties)
                                        }

                                        // ✅ NEW
                                        if !p.catches.isEmpty {
                                            sectionTitle("Catches / gotchas")
                                            bulletList(p.catches)
                                        }

                                        if p.benefits.isEmpty && p.liabilities.isEmpty && p.possiblePenalties.isEmpty && p.catches.isEmpty {
                                            Text("No party-specific items could be inferred from the text.")
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Divider().opacity(0.25)
                                }
                            }
                        }
                    }

                    if let wb = result.whoBenefitsMost {
                        Card("Who benefits most?") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(wb.party)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int(wb.confidence * 100))%")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                if !wb.reasons.isEmpty {
                                    ForEach(wb.reasons, id: \.self) { r in
                                        Text("• \(r)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Card("Key info") {
                        VStack(alignment: .leading, spacing: 10) {
                            row("Type", result.docType ?? "Unknown")
                            if let c = result.confidence {
                                row("Confidence", String(format: "%.2f", c))
                            }
                            if let u = result.urgency?.level {
                                row("Urgency", u)
                            }
                        }
                    }


                    if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
                        Card("Draft letters") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(drafts, id: \.title) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(item.title)
                                                .font(.headline)
                                            Spacer()
                                            Button {
                                                UIPasteboard.general.string = item.text
                                                copiedToast = "Copied: \(item.title)"
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.bordered)
                                        }

                                        Text(item.text)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Divider().opacity(0.25)
                                }
                            }
                        }
                    }

                    Card("Export") {
                        HStack(spacing: 10) {
                            ShareLink(item: exportText) {
                                Label("Share analysis", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                UIPasteboard.general.string = exportText
                                copiedToast = "Copied: Full export"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let lim = result.limitations, !lim.isEmpty {
                        Card("Limitations") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(lim, id: \.self) { Text("• \( $0 )") }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
        .overlay(alignment: .top) {
            if let toast = copiedToast {
                Text(toast)
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text("• \(s)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}
