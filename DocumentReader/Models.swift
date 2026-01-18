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

