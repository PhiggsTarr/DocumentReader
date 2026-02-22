import Foundation
import UIKit

enum PDFExporter {

    struct RenderOptions {
        var pageSize: CGSize = CGSize(width: 612, height: 792) // US Letter @ 72dpi
        var margin: CGFloat = 54                               // 0.75"
        var titleFont: UIFont = .systemFont(ofSize: 20, weight: .bold)
        var headingFont: UIFont = .systemFont(ofSize: 14, weight: .semibold)
        var bodyFont: UIFont = .systemFont(ofSize: 12, weight: .regular)
        var paragraphSpacing: CGFloat = 10
    }

    /// Renders a simple, professional PDF from a structured draft.
    static func makePDF(draft: PDFDraft, options: RenderOptions = .init()) throws -> Data {

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: options.pageSize))

        let data = renderer.pdfData { ctx in
            let pageRect = CGRect(origin: .zero, size: options.pageSize)
            let contentWidth = options.pageSize.width - options.margin * 2

            // Always render black ink on white page for consistency
            let ink = UIColor.black

            func beginPage() {
                ctx.beginPage()
                // Fill white background (some viewers behave oddly if not explicit)
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(pageRect)
            }

            func attributed(_ string: String, font: UIFont) -> NSAttributedString {
                NSAttributedString(string: string, attributes: [
                    .font: font,
                    .foregroundColor: ink
                ])
            }

            /// Draws attributed text with pagination; returns updated y
            func drawBlock(_ block: NSAttributedString, startY: CGFloat) -> CGFloat {
                var y = startY
                var remaining = block

                while remaining.length > 0 {
                    let maxHeight = options.pageSize.height - options.margin - y
                    if maxHeight < 40 {
                        beginPage()
                        y = options.margin
                    }

                    let drawRect = CGRect(x: options.margin, y: y, width: contentWidth, height: maxHeight)

                    // Find how much fits on this page
                    let fitRange = visibleRange(for: remaining, in: drawRect)
                    let visible = remaining.attributedSubstring(from: fitRange)

                    // Draw
                    visible.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

                    // Advance y based on actual drawn height
                    let usedHeight = visible.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    ).height

                    y += ceil(usedHeight) + options.paragraphSpacing

                    // Remove what we drew
                    if fitRange.length >= remaining.length {
                        break
                    } else {
                        remaining = remaining.attributedSubstring(from: NSRange(location: fitRange.location + fitRange.length,
                                                                               length: remaining.length - fitRange.length))
                    }

                    // Next page if still remaining
                    if remaining.length > 0 {
                        beginPage()
                        y = options.margin
                    }
                }

                return y
            }

            /// Determines visible substring range that fits within rect height.
            func visibleRange(for text: NSAttributedString, in rect: CGRect) -> NSRange {
                // Binary search length that fits
                var low = 0
                var high = text.length
                var best = 0

                while low <= high {
                    let mid = (low + high) / 2
                    let sub = text.attributedSubstring(from: NSRange(location: 0, length: mid))
                    let h = sub.boundingRect(
                        with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    ).height

                    if h <= rect.height {
                        best = mid
                        low = mid + 1
                    } else {
                        high = mid - 1
                    }
                }

                // Avoid returning 0 (infinite loop) by forcing at least a small chunk
                return NSRange(location: 0, length: max(best, min(200, text.length)))
            }

            // Start first page
            beginPage()
            var y: CGFloat = options.margin

            // Title
            let title = (draft.title ?? "Draft Response").trimmingCharacters(in: .whitespacesAndNewlines)
            y = drawBlock(attributed(title + "\n", font: options.titleFont), startY: y)

            // Sections
            let sections = draft.sections ?? []
            for sec in sections {
                let heading = (sec.heading ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let body = (sec.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if !heading.isEmpty {
                    y = drawBlock(attributed(heading + "\n", font: options.headingFont), startY: y)
                }
                if !body.isEmpty {
                    y = drawBlock(attributed(body + "\n", font: options.bodyFont), startY: y)
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
