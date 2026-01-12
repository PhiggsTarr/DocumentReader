//
//  OCRService.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/10/26.
//

import Foundation
import Vision
import UIKit

final class OCRService {
    func recognizeText(from images: [UIImage]) async throws -> String {
        var fullText = ""

        for image in images {
            guard let cgImage = image.cgImage else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let pageText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            if !pageText.isEmpty {
                fullText += (fullText.isEmpty ? "" : "\n\n") + pageText
            }
        }

        return fullText
    }
}
