//
//  RecentDocumentDetailView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/11/26.
//


import SwiftUI

struct RecentDocumentDetailView: View {
    let recent: RecentDocument
    let apiClient: APIClient

    @State private var result: DocumentAnalyzeResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color.black.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card("Document") {
                        Text(recent.fullText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(10)
                    }

                    Button {
                        Task { await analyze() }
                    } label: {
                        Text(isLoading ? "Analyzing…" : "Analyze")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    if let result {
                        Card("Actions") {
                            VStack(spacing: 12) {
                                NavigationLink {
                                    AnalysisResultView(result: result, documentText: recent.fullText, canSave: false)
                                } label: {
                                    Text("View Results")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    ChatView(documentText: recent.fullText,
                                             suggestedQuestions: result.suggestedQuestions ?? [])
                                } label: {
                                    Text("Chat about this document")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 18)
            }
        }
        .navigationTitle(recent.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func analyze() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            result = try await apiClient.analyzeDocument(text: recent.fullText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
