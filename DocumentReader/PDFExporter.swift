//
//  PDFExporter.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/12/26.
//


import Foundation
import UIKit

enum PDFExporter {

    struct RenderOptions {
        var pageSize: CGSize = CGSize(width: 612, height: 792) // US Letter @ 72dpi
        var margin: CGFloat = 54                               // 0.75"
        var titleFont: UIFont = .systemFont(ofSize: 20, weight: .bold)
        var headingFont: UIFont = .systemFont(ofSize: 14, weight: .semibold)
        var bodyFont: UIFont = .systemFont(ofSize: 12, weight: .regular)
        var lineSpacing: CGFloat = 4
    }

    /// Renders a simple, professional PDF from a structured draft.
    static func makePDF(draft: PDFDraft, options: RenderOptions = .init()) throws -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: options.pageSize))

        let data = renderer.pdfData { ctx in
            var currentY: CGFloat = options.margin
            var pageNumber = 1

            func newPage() {
                ctx.beginPage()
                currentY = options.margin
                pageNumber += 1
            }

            func drawText(_ text: String, font: UIFont, spacingAfter: CGFloat) {
                let availableWidth = options.pageSize.width - options.margin * 2
                let attr: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.label
                ]

                let attributed = NSAttributedString(string: text, attributes: attr)
                let framesetter = CTFramesetterCreateWithAttributedString(attributed)

                var currentRange = CFRangeMake(0, attributed.length)

                while currentRange.length > 0 {
                    let maxHeight = options.pageSize.height - options.margin - currentY
                    if maxHeight < 60 { // not enough room -> new page
                        newPage()
                    }

                    let pathRect = CGRect(x: options.margin, y: currentY, width: availableWidth, height: options.pageSize.height - options.margin - currentY)
                    let path = CGPath(rect: pathRect, transform: nil)

                    let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
                    let lines = CTFrameGetLines(frame) as NSArray
                    if lines.count == 0 {
                        break
                    }

                    // Measure consumed height
                    var lineOrigins = Array(repeating: CGPoint.zero, count: lines.count)
                    CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &lineOrigins)

                    var lastLineY: CGFloat = 0
                    if let last = lineOrigins.last {
                        lastLineY = last.y
                    }

                    let consumedHeight = (pathRect.height - lastLineY) + spacingAfter

                    // Draw
                    ctx.cgContext.saveGState()
                    ctx.cgContext.textMatrix = .identity
                    ctx.cgContext.translateBy(x: 0, y: options.pageSize.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, ctx.cgContext)
                    ctx.cgContext.restoreGState()

                    // Advance range
                    let visibleRange = CTFrameGetVisibleStringRange(frame)
                    let usedLen = visibleRange.length
                    currentRange = CFRangeMake(currentRange.location + usedLen, currentRange.length - usedLen)

                    // Advance Y
                    currentY += consumedHeight

                    // If more text remains, start a new page
                    if currentRange.length > 0 {
                        newPage()
                    }
                }
            }

            // Start first page
            ctx.beginPage()

            // Title
            let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty {
                drawText(title + "\n", font: options.titleFont, spacingAfter: 10)
            } else {
                drawText("Draft Response\n", font: options.titleFont, spacingAfter: 10)
            }

            // Sections
            let sections = draft.sections ?? []
            for sec in sections {
                let heading = (sec.heading ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let body = (sec.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if !heading.isEmpty {
                    drawText(heading + "\n", font: options.headingFont, spacingAfter: 6)
                }
                if !body.isEmpty {
                    drawText(body + "\n\n", font: options.bodyFont, spacingAfter: 10)
                }
            }
        }

        return data
    }

    /// Writes the PDF to a temp file and returns the file URL (perfect for ShareLink)
    static func writeToTempFile(data: Data, preferredFilename: String?) throws -> URL {
        let safeName = (preferredFilename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        ? preferredFilename!
        : "Draft-Response-\(Int(Date().timeIntervalSince1970)).pdf"

        let filename = safeName.hasSuffix(".pdf") ? safeName : (safeName + ".pdf")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }
}
