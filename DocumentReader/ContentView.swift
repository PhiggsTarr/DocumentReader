import SwiftUI
import UIKit

struct ContentView: View {
    @State private var analysisResult: DocumentAnalyzeResponse? = nil
    @State private var lastDocumentText: String = ""

    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    @State private var showScanner = false
    @State private var ocrTextPreview: String = ""

    @StateObject private var recents = RecentDocumentsStore()
    @State private var progress: Double = 0          // 0...100
    @State private var phase: LoadingPhase = .analyzing
    @State private var progressTask: Task<Void, Never>? = nil
    @StateObject private var progressModel = AnalysisProgressModel()



    private let apiClient = APIClient()
    private let ocrService = OCRService()

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        header

                        scanCard

                        if isLoading {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(phase.rawValue)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int(progress))%")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                ProgressView(value: progress, total: 100)
                                    .tint(.blue)

                                Text("This may take a few seconds depending on document length.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }


                        if !ocrTextPreview.isEmpty {
                            Card("OCR Preview") {
                                Text(ocrTextPreview)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(10)
                            }
                            .padding(.horizontal, DS.pagePadding)
                        }

                        if let result = analysisResult {
                            resultsActions(result: result)
                                .padding(.horizontal, DS.pagePadding)
                        }

                        recentDocuments
                            .padding(.horizontal, DS.pagePadding)

                        Spacer(minLength: 30)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Document Reader")
            .navigationBarTitleDisplayMode(.inline)
            .polishedNavBar()
            .sheet(isPresented: $showScanner) {
                DocumentScannerView(
                    onComplete: { images in
                        showScanner = false
                        Task { await handleScan(images: images) }
                    },
                    onCancel: { showScanner = false },
                    onError: { err in
                        showScanner = false
                        errorMessage = err.localizedDescription
                    }
                )
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .overlay {
            if progressModel.isPresented {
                AnalysisProgressOverlay(model: progressModel)
            }
        }

        .environmentObject(recents)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Scan and interpret legal documents")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            Text("Not legal advice • Informational only")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 10)
    }

    private var scanCard: some View {
        Card("Scan") {
            Button {
                showScanner = true
            } label: {
                HStack {
                    Image(systemName: "doc.viewfinder")
                    Text("Scan Document")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding(.horizontal, DS.pagePadding)
    }

    private func resultsActions(result: DocumentAnalyzeResponse) -> some View {
        Card("Next") {
            VStack(spacing: 10) {
                NavigationLink {
                    AnalysisResultView(result: result, documentText: lastDocumentText)
                } label: {
                    HStack {
                        Image(systemName: "text.magnifyingglass")
                        Text("View Analysis")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().opacity(0.4)

                NavigationLink {
                    ChatView(
                        documentText: lastDocumentText,
                        suggestedQuestions: result.suggestedQuestions ?? []
                    )
                } label: {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text("Chat about this document")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var recentDocuments: some View {
        Card("Recent documents") {
            if recents.items.isEmpty {
                Text("No recent documents yet. Scan something to get started.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(spacing: 10) {
                    ForEach(recents.items) { item in
                        NavigationLink {
                            // Load into analysis view by re-analyzing? Or just open chat with stored text.
                            ChatView(documentText: item.fullText, suggestedQuestions: [])
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)

                                    Text(item.snippet)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    recents.remove(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)

                        Divider().opacity(0.25)
                    }

                    Button(role: .destructive) {
                        recents.clear()
                    } label: {
                        Text("Clear recents")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    @MainActor
    private func handleScan(images: [UIImage]) async {
        isLoading = true
        errorMessage = nil
        analysisResult = nil
        lastDocumentText = ""
        ocrTextPreview = ""

        progressModel.start()
        progressModel.moveTo(cap: 0.18)

        defer {
            isLoading = false
        }

        do {
            // 1) OCR
            progressModel.moveTo(cap: 0.45)

            let text = try await ocrService.recognizeText(from: images)
            ocrTextPreview = text.isEmpty ? "(No text found)" : text

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 30 else {
                progressModel.stop()
                errorMessage = "OCR text is too short to analyze. Try scanning again with better lighting."
                return
            }

            // 2) API call (analyze)
            lastDocumentText = trimmed
            progressModel.moveTo(cap: 0.90)

            let result = try await apiClient.analyzeDocument(text: trimmed)

            // 3) Save + finish
            analysisResult = result
            progressModel.finishAndDismiss()

        } catch {
            progressModel.stop()
            errorMessage = error.localizedDescription
            print("❌ Flow failed:", error)
        }
    }


    
    @MainActor
    private func startAnimatedLoading() {
        progressTask?.cancel()
        progress = 0
        phase = .analyzing

        progressTask = Task { @MainActor in
            var phaseIndex = 0
            var tickCount = 0

            while !Task.isCancelled {
                // Rotate words every 2 seconds (assuming 0.2s ticks -> 10 ticks = 2s)
                if tickCount % 10 == 0 {
                    phase = LoadingPhase.rotating[phaseIndex % LoadingPhase.rotating.count]
                    phaseIndex += 1
                }

                // Move progress up, but never hit 100% until real work finishes
                // Ease slower as we approach 95%
                if progress < 95 {
                    let remaining = 95 - progress
                    let step = max(0.2, remaining * 0.03)   // slows down near 95
                    progress = min(95, progress + step)
                }

                tickCount += 1
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }
    }

    @MainActor
    private func finishAnimatedLoading(success: Bool) async {
        progressTask?.cancel()
        progressTask = nil

        if success {
            phase = .summarizing
            withAnimation(.easeOut(duration: 0.25)) {
                progress = 100
            }
            // Let user see 100% briefly
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

}




//#Preview{
//    ContentView()
//}
