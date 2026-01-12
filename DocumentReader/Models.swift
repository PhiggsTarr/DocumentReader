//
//  Models.swift
//  DocumentReader
//

import Foundation

struct DocumentAnalyzeResponse: Codable, Equatable {
    let docType: String?
    let confidence: Double?
    let summaryPlain: String?

    let simpleEnglish: String?

    // ✅ NEW: ELI5
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

struct PartyBenefitsLiabilities: Codable, Equatable, Identifiable {
    let id = UUID()
    let party: String
    let benefits: [String]
    let liabilities: [String]
    let possiblePenalties: [String]

    // ✅ NEW
    let catches: [String]

    enum CodingKeys: String, CodingKey {
        case party
        case benefits
        case liabilities
        case possiblePenalties = "possible_penalties"
        case catches
    }
}

struct WhoBenefitsMost: Codable, Equatable {
    let party: String
    let confidence: Double
    let reasons: [String]
}

struct Urgency: Codable, Equatable {
    let level: String?
    let reasons: [String]?
}

struct NextStep: Codable, Equatable, Identifiable {
    let id = UUID()
    let title: String?
    let detail: String?
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

struct LabeledValue: Codable, Equatable, Identifiable {
    let id = UUID()
    let label: String?
    let value: String?
    let source: String?
}

struct LabeledAmount: Codable, Equatable, Identifiable {
    let id = UUID()
    let label: String?
    let value: Double?
    let currency: String?
    let source: String?
}
