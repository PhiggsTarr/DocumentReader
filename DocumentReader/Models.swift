//
//  Models.swift
//  DocumentReader
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Top-level response

struct DocumentAnalyzeResponse: Codable, Equatable {
    let docType: String?
    let confidence: Double?
    let summaryPlain: String?

    let simpleEnglish: String?

    let eli5Paragraphs: [String]?
    let eli5Analogy: String?

    let partyAnalysis: [PartyBenefitsLiabilities]?
    let whoBenefitsMost: WhoBenefitsMost?

    let analysisParagraphs: [String]?
    let keyFacts: KeyFacts?
    let urgency: Urgency?
    let nextSteps: [NextStep]?
    let redFlags: [String]?
    let drafts: Drafts?
    let limitations: [String]?
    let suggestedQuestions: [String]?

    enum CodingKeys: String, CodingKey {
        case docType = "doc_type"
        case confidence
        case summaryPlain = "summary_plain"

        case simpleEnglish = "simple_english"

        case eli5Paragraphs = "eli5_paragraphs"
        case eli5Analogy = "eli5_analogy"

        case partyAnalysis = "party_analysis"
        case whoBenefitsMost = "who_benefits_most"

        case analysisParagraphs = "analysis_paragraphs"
        case keyFacts = "key_facts"
        case urgency
        case nextSteps = "next_steps"
        case redFlags = "red_flags"
        case drafts
        case limitations
        case suggestedQuestions = "suggested_questions"
    }
}

// MARK: - Party Analysis

struct PartyBenefitsLiabilities: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    let party: String
    let roleTitle: String

    let benefits: [String]
    let liabilities: [String]
    let possiblePenalties: [String]
    let catches: [String]
    let rights: [PartyRight]

    enum CodingKeys: String, CodingKey {
        // IMPORTANT: do NOT include `id`
        case party
        case roleTitle = "role_title"
        case benefits
        case liabilities
        case possiblePenalties = "possible_penalties"
        case catches
        case rights
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.party = (try? c.decode(String.self, forKey: .party)) ?? "Unknown party"
        self.roleTitle = (try? c.decode(String.self, forKey: .roleTitle)) ?? "Party"

        self.benefits = (try? c.decode([String].self, forKey: .benefits)) ?? []
        self.liabilities = (try? c.decode([String].self, forKey: .liabilities)) ?? []
        self.possiblePenalties = (try? c.decode([String].self, forKey: .possiblePenalties)) ?? []
        self.catches = (try? c.decode([String].self, forKey: .catches)) ?? []
        self.rights = (try? c.decode([PartyRight].self, forKey: .rights)) ?? []

        self.id = UUID()
    }
}

// MARK: - Rights + Citations

struct PartyRight: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    let right: String
    let details: String
    let source: String?
    let citations: [LegalCitation]

    enum CodingKeys: String, CodingKey {
        // IMPORTANT: do NOT include `id`
        case right
        case details
        case source
        case citations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.right = (try? c.decode(String.self, forKey: .right)) ?? ""
        self.details = (try? c.decode(String.self, forKey: .details)) ?? ""
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
        self.citations = (try? c.decode([LegalCitation].self, forKey: .citations)) ?? []
        self.id = UUID()
    }
}

struct LegalCitation: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    let sourceType: String   // "document" | "external"
    let source: String
    let quote: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        // IMPORTANT: do NOT include `id`
        case sourceType = "source_type"
        case source
        case quote
        case url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceType = (try? c.decode(String.self, forKey: .sourceType)) ?? "document"
        self.source = (try? c.decode(String.self, forKey: .source)) ?? ""
        self.quote = try? c.decodeIfPresent(String.self, forKey: .quote)
        self.url = try? c.decodeIfPresent(String.self, forKey: .url)
        self.id = UUID()
    }
}

// MARK: - Who benefits most

struct WhoBenefitsMost: Codable, Equatable {
    let party: String
    let confidence: Double
    let reasons: [String]
}

// MARK: - Urgency + next steps + drafts

struct Urgency: Codable, Equatable {
    let level: String?
    let reasons: [String]?
}

struct NextStep: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let title: String?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        // IMPORTANT: do NOT include `id`
        case title
        case detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try? c.decodeIfPresent(String.self, forKey: .title)
        self.detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        self.id = UUID()
    }
}

struct Drafts: Codable, Equatable {
    let responseDraftShort: String?
    let responseDraftMedium: String?
    let responseDraftLong: String?
    let questionsForAdvisor: String?

    enum CodingKeys: String, CodingKey {
        case responseDraftShort = "response_draft_short"
        case responseDraftMedium = "response_draft_medium"
        case responseDraftLong = "response_draft_long"
        case questionsForAdvisor = "questions_for_advisor"
    }

    var allDrafts: [(title: String, text: String)] {
        [
            ("Response draft (Short)", responseDraftShort),
            ("Response draft (Medium)", responseDraftMedium),
            ("Response draft (Long)", responseDraftLong),
            ("Questions for advisor", questionsForAdvisor)
        ]
        .compactMap { pair in
            guard let text = pair.1, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (pair.0, text)
        }
    }
}

// MARK: - Key facts

struct KeyFacts: Codable, Equatable {
    let parties: [String]?
    let dates: [LabeledValue]?
    let amounts: [LabeledAmount]?
    let obligations: [String]?
    let deadlines: [String]?
    let governingLaw: String?
    let keyPoints: [String]?

    enum CodingKeys: String, CodingKey {
        case parties
        case dates
        case amounts
        case obligations
        case deadlines
        case governingLaw = "governing_law"
        case keyPoints = "key_points"
    }
}

struct LabeledValue: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let label: String?
    let value: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        // IMPORTANT: do NOT include `id`
        case label
        case value
        case source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try? c.decodeIfPresent(String.self, forKey: .label)
        self.value = try? c.decodeIfPresent(String.self, forKey: .value)
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
        self.id = UUID()
    }
}

struct LabeledAmount: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let label: String?
    let value: Double?
    let currency: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        // IMPORTANT: do NOT include `id`
        case label
        case value
        case currency
        case source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try? c.decodeIfPresent(String.self, forKey: .label)
        self.value = try? c.decodeIfPresent(Double.self, forKey: .value)
        self.currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
        self.id = UUID()
    }
}

// MARK: - AnalysisResultView (your existing view, unchanged except it depends on the fixed models)

//struct AnalysisResultView: View {
//    let result: DocumentAnalyzeResponse
//    let documentText: String
//
//    @State private var copiedToast: String?
//
//    private var exportText: String {
//        var parts: [String] = []
//        parts.append("Document type: \(result.docType ?? "Unknown")")
//        if let c = result.confidence { parts.append("Confidence: \(String(format: "%.2f", c))") }
//        parts.append("")
//
//        if let wb = result.whoBenefitsMost {
//            parts.append("Who benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
//            if !wb.reasons.isEmpty {
//                parts.append("Reasons:")
//                parts.append(contentsOf: wb.reasons.map { "- \($0)" })
//            }
//            parts.append("")
//        }
//
//        parts.append("Summary:")
//        parts.append(result.summaryPlain ?? "(none)")
//        parts.append("")
//
//        if let simple = result.simpleEnglish, !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//            parts.append("Explanation in simple English:")
//            parts.append(simple)
//            parts.append("")
//        }
//
//        if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
//            parts.append("Explain like I'm 5:")
//            parts.append(eli5[0])
//            parts.append("")
//            parts.append(eli5[1])
//            parts.append("")
//        }
//        if let analogy = result.eli5Analogy, !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//            parts.append("ELI5 Analogy:")
//            parts.append(analogy)
//            parts.append("")
//        }
//
//        if let parties = result.partyAnalysis, !parties.isEmpty {
//            parts.append("Benefits, liabilities, possible penalties, and catches by party:")
//            for p in parties {
//                parts.append("\n\(p.party):")
//
//                if !p.benefits.isEmpty {
//                    parts.append("  Benefits:")
//                    parts.append(contentsOf: p.benefits.map { "  - \($0)" })
//                }
//
//                if !p.liabilities.isEmpty {
//                    parts.append("  Liabilities / obligations:")
//                    parts.append(contentsOf: p.liabilities.map { "  - \($0)" })
//                }
//
//                if !p.possiblePenalties.isEmpty {
//                    parts.append("  Possible penalties / consequences:")
//                    parts.append(contentsOf: p.possiblePenalties.map { "  - \($0)" })
//                }
//
//                if !p.catches.isEmpty {
//                    parts.append("  Catches / gotchas:")
//                    parts.append(contentsOf: p.catches.map { "  - \($0)" })
//                }
//            }
//            parts.append("")
//        }
//
//        if let paras = result.analysisParagraphs, !paras.isEmpty {
//            parts.append("Detailed analysis:")
//            parts.append(contentsOf: paras.map { "- \($0)" })
//            parts.append("")
//        }
//
//        if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
//            parts.append("Drafts:")
//            for d in drafts {
//                parts.append("\n\(d.title):\n\(d.text)\n")
//            }
//        }
//
//        if let lim = result.limitations, !lim.isEmpty {
//            parts.append("\nLimitations:")
//            parts.append(contentsOf: lim.map { "- \($0)" })
//        }
//
//        return parts.joined(separator: "\n")
//    }
//
//    var body: some View {
//        ZStack {
//            ScreenBackground()
//
//            ScrollView {
//                VStack(spacing: 14) {
//
//                    Card("Summary") {
//                        VStack(alignment: .leading, spacing: 10) {
//                            Text(result.summaryPlain ?? "No summary returned.")
//                                .frame(maxWidth: .infinity, alignment: .leading)
//
//                            if let wb = result.whoBenefitsMost {
//                                Divider().opacity(0.25)
//                                Text("Likely benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
//                                    .font(.subheadline.weight(.semibold))
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                    }
//
//                    if let paras = result.analysisParagraphs, !paras.isEmpty {
//                        Card("Detailed analysis") {
//                            VStack(alignment: .leading, spacing: 10) {
//                                ForEach(paras.indices, id: \.self) { i in
//                                    Text(paras[i])
//                                        .frame(maxWidth: .infinity, alignment: .leading)
//                                    if i != paras.count - 1 { Divider().opacity(0.25) }
//                                }
//                            }
//                            .foregroundStyle(.secondary)
//                        }
//                    }
//
//                    if let simple = result.simpleEnglish,
//                       !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                        Card("Explanation in simple English") {
//                            Text(simple)
//                                .frame(maxWidth: .infinity, alignment: .leading)
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//
//                    if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
//                        Card("Explain like I’m 5") {
//                            VStack(alignment: .leading, spacing: 10) {
//                                Text(eli5[0])
//                                    .foregroundStyle(.secondary)
//                                    .frame(maxWidth: .infinity, alignment: .leading)
//
//                                Divider().opacity(0.25)
//
//                                Text(eli5[1])
//                                    .foregroundStyle(.secondary)
//                                    .frame(maxWidth: .infinity, alignment: .leading)
//
//                                if let analogy = result.eli5Analogy,
//                                   !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//                                    Divider().opacity(0.25)
//                                    Text("Analogy")
//                                        .font(.subheadline.weight(.semibold))
//                                        .foregroundStyle(.secondary)
//                                    Text(analogy)
//                                        .foregroundStyle(.secondary)
//                                        .frame(maxWidth: .infinity, alignment: .leading)
//                                }
//                            }
//                        }
//                    }
//
//                    if let parties = result.partyAnalysis, !parties.isEmpty {
//                        Card("Benefits, liabilities, penalties & catches") {
//                            VStack(alignment: .leading, spacing: 14) {
//                                ForEach(parties) { p in
//                                    VStack(alignment: .leading, spacing: 10) {
//                                        Text(p.roleTitle)
//                                            .font(.headline)
//                                            .fontWeight(.bold)
//
//                                        Text(p.party)
//                                            .font(.subheadline)
//                                            .foregroundStyle(.secondary)
//
//                                        if !p.benefits.isEmpty {
//                                            sectionTitle("Benefits")
//                                            bulletList(p.benefits)
//                                            Divider()
//                                        }
//
//                                        if !p.liabilities.isEmpty {
//                                            sectionTitle("Liabilities / obligations")
//                                            bulletList(p.liabilities)
//                                            Divider()
//                                        }
//
//                                        if !p.possiblePenalties.isEmpty {
//                                            sectionTitle("Possible penalties / consequences")
//                                            bulletList(p.possiblePenalties)
//                                            Divider()
//                                        }
//
//                                        if !p.catches.isEmpty {
//                                            sectionTitle("Catches / gotchas")
//                                            bulletList(p.catches)
//                                        }
//
//                                        if !p.rights.isEmpty {
//                                            sectionTitle("Rights")
//                                            ForEach(p.rights) { r in
//                                                Text("• \(r.right): \(r.details)")
//                                                    .foregroundStyle(.secondary)
//
//                                                if !r.citations.isEmpty {
//                                                    ForEach(r.citations.indices, id: \.self) { i in
//                                                        let c = r.citations[i]
//                                                        Text("↳ \(c.source)\(c.quote.map { " — “\($0)”" } ?? "")")
//                                                            .font(.footnote)
//                                                            .foregroundStyle(.secondary.opacity(0.85))
//                                                    }
//                                                }
//                                            }
//                                        }
//
//                                        if p.benefits.isEmpty && p.liabilities.isEmpty && p.possiblePenalties.isEmpty && p.catches.isEmpty && p.rights.isEmpty {
//                                            Text("No party-specific items could be inferred from the text.")
//                                                .foregroundStyle(.secondary)
//                                            Divider()
//                                        }
//                                    }
//                                }
//                            }
//                        }
//                    }
//
//                    if let wb = result.whoBenefitsMost {
//                        Card("Who benefits most?") {
//                            VStack(alignment: .leading, spacing: 8) {
//                                HStack {
//                                    Text(wb.party)
//                                        .font(.headline)
//                                    Spacer()
//                                    Text("\(Int(wb.confidence * 100))%")
//                                        .font(.subheadline.monospacedDigit())
//                                        .foregroundStyle(.secondary)
//                                }
//
//                                if !wb.reasons.isEmpty {
//                                    ForEach(wb.reasons, id: \.self) { r in
//                                        Text("• \(r)")
//                                            .foregroundStyle(.secondary)
//                                    }
//                                }
//                            }
//                        }
//                    }
//
//                    Card("Key info") {
//                        VStack(alignment: .leading, spacing: 10) {
//                            row("Type", result.docType ?? "Unknown")
//                            if let c = result.confidence { row("Confidence", String(format: "%.2f", c)) }
//                            if let u = result.urgency?.level { row("Urgency", u) }
//                        }
//                    }
//
//                    if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
//                        Card("Draft letters") {
//                            VStack(alignment: .leading, spacing: 14) {
//                                ForEach(drafts, id: \.title) { item in
//                                    VStack(alignment: .leading, spacing: 8) {
//                                        HStack {
//                                            Text(item.title).font(.headline)
//                                            Spacer()
//                                            Button {
//                                                UIPasteboard.general.string = item.text
//                                                copiedToast = "Copied: \(item.title)"
//                                            } label: {
//                                                Image(systemName: "doc.on.doc")
//                                            }
//                                            .buttonStyle(.bordered)
//                                        }
//
//                                        Text(item.text)
//                                            .foregroundStyle(.secondary)
//                                            .frame(maxWidth: .infinity, alignment: .leading)
//                                    }
//                                    Divider().opacity(0.25)
//                                }
//                            }
//                        }
//                    }
//
//                    Card("Export") {
//                        HStack(spacing: 10) {
//                            ShareLink(item: exportText) {
//                                Label("Share analysis", systemImage: "square.and.arrow.up")
//                            }
//                            .buttonStyle(.borderedProminent)
//
//                            Button {
//                                UIPasteboard.general.string = exportText
//                                copiedToast = "Copied: Full export"
//                            } label: {
//                                Label("Copy", systemImage: "doc.on.doc")
//                            }
//                            .buttonStyle(.bordered)
//                        }
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                    }
//
//                    if let lim = result.limitations, !lim.isEmpty {
//                        Card("Limitations") {
//                            VStack(alignment: .leading, spacing: 6) {
//                                ForEach(lim, id: \.self) { Text("• \( $0 )") }
//                            }
//                            .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//                .padding(.horizontal, DS.pagePadding)
//                .padding(.top, 12)
//                .padding(.bottom, 30)
//            }
//        }
//        .navigationTitle("Analysis")
//        .navigationBarTitleDisplayMode(.inline)
//        .polishedNavBar()
//        .overlay(alignment: .top) {
//            if let toast = copiedToast {
//                Text(toast)
//                    .font(.footnote.weight(.semibold))
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 8)
//                    .background(.ultraThinMaterial)
//                    .clipShape(Capsule())
//                    .padding(.top, 10)
//                    .transition(.move(edge: .top).combined(with: .opacity))
//                    .onAppear {
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
//                            withAnimation { copiedToast = nil }
//                        }
//                    }
//            }
//        }
//    }
//
//    private func sectionTitle(_ text: String) -> some View {
//        Text(text)
//            .font(.headline)
//            .fontWeight(.bold)
//            .foregroundStyle(.primary)
//            .padding(.top, 4)
//    }
//
//    private func bulletList(_ items: [String]) -> some View {
//        VStack(alignment: .leading, spacing: 6) {
//            ForEach(items, id: \.self) { s in
//                Text("• \(s)")
//                    .foregroundStyle(.secondary)
//            }
//        }
//    }
//
//    private func row(_ k: String, _ v: String) -> some View {
//        HStack {
//            Text(k).foregroundStyle(.secondary)
//            Spacer()
//            Text(v).fontWeight(.semibold)
//        }
//        .font(.subheadline)
//    }
//}
