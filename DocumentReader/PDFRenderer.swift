//
//  PDFRenderer.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/12/26.
//


import UIKit

enum PDFRenderer {
    static func render(draft: PDFDraft) throws -> URL {
        let filename = (draft.filename?.isEmpty == false ? draft.filename! : "Custom-Response.pdf")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let margin: CGFloat = 54
        let contentWidth = pageRect.width - margin * 2

        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let headerFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let sectionTitleFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y = margin

            func drawLine(_ text: String, font: UIFont, spacing: CGFloat = 6) {
                let attr: [NSAttributedString.Key: Any] = [.font: font]
                let size = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attr,
                    context: nil
                ).size

                if y + size.height > pageRect.height - margin {
                    ctx.beginPage()
                    y = margin
                }

                (text as NSString).draw(
                    with: CGRect(x: margin, y: y, width: contentWidth, height: size.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attr,
                    context: nil
                )
                y += size.height + spacing
            }

            // Title
            if let t = draft.title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawLine(t, font: titleFont, spacing: 14)
            }

            // Header block
            let date = draft.header?.date ?? ""
            let from = draft.header?.from ?? ""
            let to = draft.header?.to ?? ""
            let subject = draft.header?.subject ?? ""

            if !date.isEmpty { drawLine(date, font: headerFont, spacing: 4) }
            if !from.isEmpty { drawLine("From: \(from)", font: headerFont, spacing: 4) }
            if !to.isEmpty { drawLine("To: \(to)", font: headerFont, spacing: 4) }
            if !subject.isEmpty {
                y += 6
                drawLine("Subject: \(subject)", font: headerFont, spacing: 10)
            } else {
                y += 10
            }

            // Salutation
            if let sal = draft.salutation, !sal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawLine(sal, font: bodyFont, spacing: 12)
            }

            // Sections
            let sections = draft.sections ?? []
            for s in sections {
                let heading = (s.heading ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let body = (s.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if !heading.isEmpty {
                    drawLine(heading, font: sectionTitleFont, spacing: 6)
                }
                if !body.isEmpty {
                    drawLine(body, font: bodyFont, spacing: 12)
                }
            }

            // Closing + signature
            if let closing = draft.closing, !closing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                y += 10
                drawLine(closing, font: bodyFont, spacing: 18)
            }

            if let sig = draft.signatureLine, !sig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawLine(sig, font: bodyFont, spacing: 0)
            }
        }

        return url
    }
}
