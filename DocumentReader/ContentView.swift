//
//  ContentView.swift
//  DocumentReader
//
//  Home screen + scan tips + low-light detection
//

//
//  ContentView.swift
//  DocumentReader
//
//  Home screen + scan tips + low-light detection
//

import SwiftUI
import UIKit
import CoreImage
import CoreData

struct ContentView: View {
    @State private var analysisResult: DocumentAnalyzeResponse? = nil
    @State private var lastDocumentText: String = ""

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var activeConversationId: String = UUID().uuidString

    @State private var showScanner = false
    @State private var ocrTextPreview: String = ""

    @StateObject private var recents = RecentDocumentsStore()
    @StateObject private var progressModel = AnalysisProgressModel()

    // ✅ Cancellable analysis task (so user can cancel and keep scan credit)
    @State private var analysisTask: Task<Void, Never>? = nil

    @State private var showPaywall = false
    @State private var showSettings = false

    @State private var lightingWarning: String? = nil
    @State private var showDimLightAlert: Bool = false

    private let apiClient = APIClient()
    private let ocrService = OCRService()

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \StoredDocument.lastOpenedAt, ascending: false)],
        animation: .default
    )
    private var savedDocs: FetchedResults<StoredDocument>

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        scanCard

                        if let w = lightingWarning {
                            NoticeBanner(
                                title: "Scene looks a bit dark",
                                message: w,
                                icon: "exclamationmark.triangle.fill"
                            )
                            .padding(.horizontal, DS.pagePadding)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if let result = analysisResult {
                            resultPreview(result: result)
                                .padding(.horizontal, DS.pagePadding)

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
            .navigationTitle("Document Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .polishedNavBar()

            .sheet(isPresented: $showScanner) {
                DocumentScannerView(
                    onComplete: { images in
                        showScanner = false

                        // ✅ Cancel any previous run (safety)
                        analysisTask?.cancel()

                        // ✅ Kick off cancellable flow
                        analysisTask = Task { await handleScan(images: images) }
                    },
                    onCancel: { showScanner = false },
                    onError: { err in
                        showScanner = false
                        errorMessage = err.localizedDescription
                    }
                )
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PaywallView()
                }
            }

            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }

            .alert("Low light detected", isPresented: $showDimLightAlert) {
                Button("Rescan") { showScanner = true }
                Button("Continue", role: .cancel) { }
            } message: {
                Text("Turn on a lamp or move near a window. Avoid shadows and glare for accurate scan.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .overlay {
            if progressModel.isPresented {
                // ✅ If your overlay already supports an onCancel closure, use this init:
                AnalysisProgressOverlay(model: progressModel) {
                    cancelCurrentAnalysis()
                }

                // If your current AnalysisProgressOverlay has no closure init,
                // add one (a cancel button) and call `onCancel()` from it.
            }
        }
        .environmentObject(recents)
        .task {
            // Keep entitlement fresh when app loads
            await purchaseManager.refreshEntitlements()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text("Scan and interpret legal documents")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
                Text("Not legal advice • Informational only")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
            }

            HStack(spacing: 8) {
                Pill(text: "Informational only", icon: "info.circle.fill", tone: .neutral)
                Pill(text: "Not legal advice", icon: "shield.lefthalf.filled", tone: .warning)
            }

            if !purchaseManager.isPro {
                Text("Free scans remaining: \(purchaseManager.freeScansRemaining)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text("Pro unlocked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DS.pagePadding)
    }

    // MARK: - Scan card

    private var scanCard: some View {
        Card("Scan", icon: "doc.viewfinder", tint: .blue) {
            VStack(spacing: 12) {
                Button {
                    attemptStartScan()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.viewfinder")
                        Text(isLoading ? "Working…" : "Scan Document")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Analyzing…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, DS.pagePadding)
    }

    private func attemptStartScan() {
        guard !isLoading else { return }

        if ScanGate.canStartScan(purchaseManager: purchaseManager) {
            // ✅ IMPORTANT: do NOT consume a scan credit here.
            // We will consume ONLY after analysis succeeds, so canceling keeps the credit.
            showScanner = true
        } else {
            showPaywall = true
        }
    }

    // MARK: - Result preview + actions

    private func resultPreview(result: DocumentAnalyzeResponse) -> some View {
        Card("Latest result", icon: "sparkles", tint: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(result.docType ?? "Unknown")
                        .font(.headline)
                    Spacer()
                    if let c = result.confidence {
                        Text("\(Int(c * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        AnalysisResultView(result: result, documentText: lastDocumentText, canSave: false)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }

                Text(result.summaryPlain ?? "No summary returned.")
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func resultsActions(result: DocumentAnalyzeResponse) -> some View {
        Card("Next", icon: "arrow.right.circle.fill", tint: .mint) {
            VStack(spacing: 10) {
                NavigationLink {
                    AnalysisResultView(result: result, documentText: lastDocumentText, canSave: true)
                } label: {
                    rowLink(icon: "text.magnifyingglass", title: "View Analysis")
                }

                Divider().opacity(0.35)

                NavigationLink {
                    ChatView(
                        conversationId: ConversationId.fromDocumentText(lastDocumentText),
                        documentText: lastDocumentText,
                        suggestedQuestions: result.suggestedQuestions ?? []
                    )
                } label: {
                    rowLink(icon: "bubble.left.and.bubble.right", title: "Chat about this document")
                }
            }
        }
    }

    private var recentDocuments: some View {
        Card("Recent documents", icon: "clock.fill", tint: .gray) {

            // --------------------------
            // 1) Recents
            // --------------------------
            if recents.items.isEmpty {
                Text("No recent documents yet. Scan something to get started.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(spacing: 10) {
                    ForEach(recents.items) { item in
                        NavigationLink {
                            ChatView(
                                conversationId: ConversationId.fromDocumentText(item.fullText),
                                documentText: item.fullText,
                                suggestedQuestions: []
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))

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
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } label: {
                        Text("Clear recents")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // --------------------------------
            // 2) Saved documents (CoreData)
            // --------------------------------
            Divider().opacity(0.35)
                .padding(.vertical, 6)

            HStack {
                Text("Saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(savedDocs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if savedDocs.isEmpty {
                Text("No saved documents yet. Tap Save after an analysis to keep it here.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 10) {
                    ForEach(savedDocs) { doc in
                        NavigationLink {
                            StoredDocumentDetailView(document: doc)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "tray.full")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(doc.title ?? "Untitled")
                                        .font(.subheadline.weight(.semibold))

                                    Text(doc.docType ?? "Saved document")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    let date = (doc.lastOpenedAt ?? doc.createdAt ?? Date())
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    context.delete(doc)
                                    try? context.save()
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                        for doc in savedDocs {
                            context.delete(doc)
                        }
                        try? context.save()
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } label: {
                        Text("Clear saved")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func rowLink(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(title).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }

    // MARK: - Cancel

    @MainActor
    private func cancelCurrentAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil

        // Stop UI
        progressModel.stop()
        isLoading = false

        // ✅ No credit was consumed yet, so cancel keeps the scan credit automatically.
    }

    // MARK: - Flow

    @MainActor
    private func handleScan(images: [UIImage]) async {
        isLoading = true
        errorMessage = nil
        analysisResult = nil
        lastDocumentText = ""
        ocrTextPreview = ""
        lightingWarning = nil
        showDimLightAlert = false

        progressModel.start()
        progressModel.moveTo(cap: 0.18)

        defer { isLoading = false }

        do {
            try Task.checkCancellation()

            let lighting = LightingAnalyzer.evaluate(images: images)
            if case .dim = lighting {
                lightingWarning =
                """
                Try turning on a lamp, moving closer to a window, and avoiding shadows.
                Keep the phone steady and make sure the entire page is in frame.
                """
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showDimLightAlert = true
            }

            progressModel.moveTo(cap: 0.45)
            try Task.checkCancellation()

            let text = try await ocrService.recognizeText(from: images)
            try Task.checkCancellation()

            ocrTextPreview = text.isEmpty ? "(No text found)" : text

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 30 else {
                progressModel.stop()
                errorMessage = "Scanned text is too short to analyze. Try scanning again with better lighting."
                return
            }

            lastDocumentText = trimmed
            progressModel.moveTo(cap: 0.90)

            try Task.checkCancellation()

            let result = try await apiClient.analyzeDocument(text: trimmed)

            try Task.checkCancellation()

            // ✅ SUCCESS
            analysisResult = result
            recents.add(fullText: trimmed, analysis: result)
            progressModel.finishAndDismiss()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // ✅ Consume scan credit ONLY after we have a successful analysis result
            purchaseManager.consumeFreeScanIfNeeded()

        } catch is CancellationError {
            // User canceled mid-flight → keep credit (we haven’t consumed it yet)
            progressModel.stop()
            return
        } catch {
            progressModel.stop()
            errorMessage = error.localizedDescription
            print("❌ Flow failed:", error)
        }
    }
}

// MARK: - Local subviews (UNCHANGED)

private struct NoticeBanner: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Lighting analyzer (UNCHANGED)

private enum LightingQuality {
    case good
    case dim(score: CGFloat)
}

private final class LightingAnalyzer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func averageBrightness(for image: UIImage) -> CGFloat? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0

        return (0.2126 * r + 0.7152 * g + 0.0722 * b)
    }

    static func evaluate(images: [UIImage]) -> LightingQuality {
        guard let first = images.first, let b = averageBrightness(for: first) else {
            return .good
        }
        if b < 0.26 { return .dim(score: b) }
        return .good
    }
}
