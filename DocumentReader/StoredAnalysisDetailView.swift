//
//  StoredAnalysisDetailView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/14/26.
//


import SwiftUI

struct StoredAnalysisDetailView: View {
    let analysis: StoredAnalysis

    private var decoded: DocumentAnalyzeResponse? {
        guard let data = analysis.analysisJSON else { return nil }
        return try? JSONDecoder().decode(DocumentAnalyzeResponse.self, from: data)
    }

    var body: some View {
        Group {
            if let decoded {
                AnalysisResultView(
                    result: decoded,
                    documentText: analysis.document?.documentText ?? "", canSave: false
                )
            } else {
                ZStack {
                    ScreenBackground()
                    Text("Couldn’t load this analysis.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
