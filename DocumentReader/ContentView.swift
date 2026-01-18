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

    // Lighting guidance
    @State private var lightingWarning: String? = nil
    @State private var showDimLightAlert: Bool = false

    private let apiClient = APIClient()
    private let ocrService = OCRService()
    
    @Environment(\.managedObjectContext) private var context

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
                       // scanTipsCard

                        if let w = lightingWarning {
                            NoticeBanner(
                                title: "Scene looks a bit dark",
                                message: w,
                                icon: "exclamationmark.triangle.fill"
                            )
                            .padding(.horizontal, DS.pagePadding)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

//                        if !ocrTextPreview.isEmpty {
//                            DisclosureCardHome("OCR Preview", icon: "text.viewfinder", tint: .teal, defaultExpanded: false) {
//                                Text(ocrTextPreview)
//                                    .font(.callout)
//                                    .foregroundStyle(.secondary)
//                                    .frame(maxWidth: .infinity, alignment: .leading)
//                                    .lineLimit(14)
//                            }
//                            .padding(.horizontal, DS.pagePadding)
//                        }

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

            .alert("Low light detected", isPresented: $showDimLightAlert) {
                Button("Rescan") { showScanner = true }
                Button("Continue", role: .cancel) { }
            } message: {
                Text("Turn on a lamp or move near a window. Avoid shadows and glare for accurate scan.")
            }
        }
        .overlay {
            if progressModel.isPresented {
                AnalysisProgressOverlay(model: progressModel)
            }
        }
        .environmentObject(recents)
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
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DS.pagePadding)
    }

    // MARK: - Scan card

    private var scanCard: some View {
        Card("Scan", icon: "doc.viewfinder", tint: .blue) {
            VStack(spacing: 12) {
                Button {
                    showScanner = true
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

    // MARK: - Scan tips

    private var scanTipsCard: some View {
        Card("Photo tips", icon: "lightbulb.fill", tint: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                tipRow("lamp.desk.fill", "Add light", "Turn on a lamp or move closer to a window.")
                tipRow("doc.text.viewfinder", "Fill the frame", "Keep the entire page inside the borders.")
                tipRow("iphone", "Hold steady", "Rest your elbows or place the paper flat.")
                tipRow("sparkles", "Avoid glare", "Tilt the page slightly if you see reflections.")
            }
        }
        .padding(.horizontal, DS.pagePadding)
    }

    private func tipRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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
                    }
                    label: {
                        
                    }
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
                        conversationId: ConversationId.fromDocumentText(lastDocumentText), documentText: lastDocumentText,
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
            // 1) Your existing Recents
            // --------------------------
            if recents.items.isEmpty {
                Text("No recent documents yet. Scan something to get started.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                VStack(spacing: 10) {
                    ForEach(recents.items) { item in
                        NavigationLink {
                            ChatView(conversationId: ConversationId.fromDocumentText(item.fullText), documentText: item.fullText, suggestedQuestions: [])
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
            // 2) NEW: Saved documents (CoreData)
            // --------------------------------
            Divider().opacity(0.35)
                .padding(.vertical, 6)

            HStack {
                Text("Saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                // Optional: quick count
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
                            // This should show the saved analyses for that document
                            StoredDocumentDetailView(document: doc)
                          //  StoredDocumentDetailView(document: doc)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "tray.full")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(doc.title ?? "Untitled")
                                        .font(.subheadline.weight(.semibold))

                                    // Show docType or a preview
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
            let text = try await ocrService.recognizeText(from: images)
            ocrTextPreview = text.isEmpty ? "(No text found)" : text

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 30 else {
                progressModel.stop()
                errorMessage = "OCR text is too short to analyze. Try scanning again with better lighting."
                return
            }

            lastDocumentText = trimmed
            progressModel.moveTo(cap: 0.90)
            let result = try await apiClient.analyzeDocument(text: trimmed)

            analysisResult = result
            recents.add(fullText: trimmed, analysis: result)
            progressModel.finishAndDismiss()

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        } catch {
            progressModel.stop()
            errorMessage = error.localizedDescription
            print("❌ Flow failed:", error)
        }
    }
}

// MARK: - Local subviews

private struct DisclosureCardHome<Content: View>: View {
    let title: String
    let icon: String?
    let tint: Color?
    let defaultExpanded: Bool
    let content: Content

    @State private var isExpanded: Bool

    init(_ title: String,
         icon: String? = nil,
         tint: Color? = nil,
         defaultExpanded: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.defaultExpanded = defaultExpanded
        self.content = content()
        self._isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        Card(nil) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    SectionHeader(title: title, icon: icon, tint: tint)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.25)
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

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

// MARK: - Lighting analyzer

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

private enum ConversationIdProvider {
    static func fromText(_ text: String) -> String {
        // Stable “conversation” id for a given document text
        // (so PDFs can be rediscovered later)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "doc-\(sha256Hex(trimmed))"
    }

    private static func sha256Hex(_ s: String) -> String {
        // Simple stable hash. If you already have CryptoKit, use SHA256 there instead.
        // This fallback is fine for an id, not for security.
        var hasher = Hasher()
        hasher.combine(s)
        return String(hasher.finalize())
    }
}
