//
//  PDFDraft.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/12/26.
//


import Foundation

struct PDFDraft: Codable, Equatable {
    var filename: String?
    var title: String?
    var header: PDFDraftHeader?
    var salutation: String?
    var sections: [PDFDraftSection]?
    var closing: String?
    var signatureLine: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case title
        case header
        case salutation
        case sections
        case closing
        case signatureLine = "signature_line"
    }
}

struct PDFDraftHeader: Codable, Equatable {
    var date: String?
    var from: String?
    var to: String?
    var subject: String?
}

struct PDFDraftSection: Codable, Equatable, Identifiable {
    let id = UUID()
    var heading: String?
    var body: String?

    enum CodingKeys: String, CodingKey {
        case heading, body
    }
}
