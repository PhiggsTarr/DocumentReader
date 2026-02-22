//
//  ContentView.swift
//  DocumentReader
//
//  Home screen + scan tips + low-light detection + PDF import
//

import SwiftUI
import UIKit
import CoreImage
import CoreData
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var analysisResult: DocumentAnalyzeResponse? = nil
    @State private var lastDocumentText: String = ""

    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    @State private var showScanner = false
    @State private var showPDFImporter = false

    @StateObject private var recents = RecentDocumentsStore()
    @StateObject private var progressModel = AnalysisProgressModel()

    // Cancellable analysis task (so user can cancel and keep scan credit)
    @State private var analysisTask: Task<Void, Never>? = nil

    @State private var showPaywall = false
    @State private var lightingWarning: String? = nil
    @State private var showDimLightAlert: Bool = false
    @State private var showChatForLatest = false
    @State private var glow = false
    @State private var deepAnalysisResult: DocumentAnalyzeResponse? = nil
    @State private var deepAnalysisSourceHash: String? = nil   // ties deep analysis to a specific document text
    
    @State private var progressCreepTask: Task<Void, Never>? = nil

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

                            // ✅ Deeper Analysis summary preview (only after it exists)
                            if let deep = deepAnalysisResult {
                                deepResultPreview(result: deep)
                                    .padding(.horizontal, DS.pagePadding)
                            }

                            resultsActions(result: result)
                                .padding(.horizontal, DS.pagePadding)
                        }

                        recentDocuments
                            .padding(.horizontal, DS.pagePadding)

                        Spacer(minLength: 30)
                    }
                    .padding(.top, 12)
                    
                    Text("We can make mistakes • Check important info. • Not legal advice")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.65))
                }
                
                
            }
            .navigationTitle("Document Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .polishedNavBar()

            // Camera scanner
            .sheet(isPresented: $showScanner) {
                // IMPORTANT:
                // This assumes your DocumentScannerView has this initializer:
                // DocumentScannerView(onComplete:onCancel:onError:)
                // If your scanner only takes onComplete, tell me its initializer and I’ll match it.
                DocumentScannerView(
                    onComplete: { images in
                        showScanner = false
                        analysisTask?.cancel()
                        analysisTask = Task { await handleScan(images: images) }
                    },
                    onCancel: { showScanner = false },
                    onError: { err in
                        showScanner = false
                        errorMessage = err.localizedDescription
                    }
                )
            }

            // PDF Importer (Files app)
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await handleImportedPDF(url: url) }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }

            .sheet(isPresented: $showPaywall) {
                NavigationStack { PaywallView() }
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
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
        }
        .overlay {
            if progressModel.isPresented {
                AnalysisProgressOverlay(model: progressModel) {
                    cancelCurrentAnalysis()
                }
            }
        }
        .environmentObject(recents)
        .task {
            await purchaseManager.ensureProductsLoaded()
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
                    .font(.title2)
                    .fontWeight(.heavy)
                    .foregroundStyle(.primary)
            } else {
                Text("Pro unlocked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DS.pagePadding)
    }

    // MARK: - Scan card (Camera + PDF)

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

                Button {
                    attemptImportPDF()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                        Text("Upload Document")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.up.doc")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
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
    
    @MainActor
    private func startProgressCreep(from start: Double = 0.55, to end: Double = 0.99) {
        progressCreepTask?.cancel()

        progressCreepTask = Task { @MainActor in
            var current = start
            // creep upwards in small steps every ~350ms
            while !Task.isCancelled, current < end, isLoading {
                try? await Task.sleep(nanoseconds: 350_000_000)

                // ease: slower as it approaches end
                let remaining = end - current
                let step = max(0.002, remaining * 0.08) // adaptive step
                current = min(end, current + step)

                progressModel.moveTo(cap: current)
            }
        }
    }

    @MainActor
    private func stopProgressCreep() {
        progressCreepTask?.cancel()
        progressCreepTask = nil
    }


    private func attemptStartScan() {
        guard !isLoading else { return }

        if ScanGate.canStartScan(purchaseManager: purchaseManager) {
            showScanner = true
        } else {
            showPaywall = true
        }
    }

    private func attemptImportPDF() {
        guard !isLoading else { return }

        if ScanGate.canStartScan(purchaseManager: purchaseManager) {
            showPDFImporter = true
        } else {
            showPaywall = true
        }
    }

    // MARK: - Result preview + actions (DEFINED here so your "cannot find" errors go away)

    private func resultPreview(result: DocumentAnalyzeResponse) -> some View {
        NavigationLink {
            AnalysisResultView(result: result, documentText: lastDocumentText, canSave: true)
        } label: {
            Card("Latest result", icon: "sparkles", tint: .purple) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(displayDocType(result.docType))
                            .font(.headline)
                        Spacer()
                        if let c = result.confidence {
                            Text("\(Int(c * 100))%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(result.summaryPlain ?? "No summary returned.")
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().opacity(0.25)

                    // Optional: keep the hint row (still opens Analysis because the whole card is a link)
                    NavigationLink {
                        AnalysisResultView(result: result, documentText: lastDocumentText, canSave: true)
                    } label: {
                        rowLink(icon: "text.magnifyingglass", title: "Tap anywhere to view analysis")
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
        .buttonStyle(.plain) // so it doesn’t look like a big blue link
        .sheet(isPresented: $showChatForLatest) {
            NavigationStack {
                ChatView(
                    conversationId: ConversationId.fromDocumentText(lastDocumentText),
                    documentText: lastDocumentText,
                    suggestedQuestions: result.suggestedQuestions ?? []
                )
            }
        }
    }
    
    private func deepResultPreview(result: DocumentAnalyzeResponse) -> some View {
        NavigationLink {
            AnalysisResultView(result: result, documentText: lastDocumentText, canSave: true)
        } label: {
            Card("Deeper Analysis Summary", icon: "brain.head.profile", tint: .indigo) {
                VStack(alignment: .leading, spacing: 10) {

                    HStack {
                        Text(displayDocType(result.docType))
                            .font(.headline)
                        Spacer()
                        if let c = result.confidence {
                            Text("\(Int(c * 100))%")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(result.summaryPlain ?? "No summary returned.")
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().opacity(0.25)

                    rowLink(icon: "text.magnifyingglass", title: "Tap anywhere to view analysis")
                        .opacity(0.85)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func displayDocType(_ raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "Unknown" }

        // If it's already human-friendly (has spaces and any uppercase), keep it
        if s.contains(" ") && s.rangeOfCharacter(from: .uppercaseLetters) != nil {
            return s
        }

        // Convert snake_case / kebab-case to Title Case
        let normalized = s
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { word -> String in
                let w = String(word).lowercased()
                // keep common acronyms uppercase
                if ["pdf", "usa", "llc", "inc", "w2", "i9", "ssn"].contains(w) { return w.uppercased() }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }



    private func resultsActions(result: DocumentAnalyzeResponse) -> some View {

        let currentHash = docHash(lastDocumentText)
        let alreadyRanForThisDoc = (deepAnalysisSourceHash == currentHash) && (deepAnalysisResult != nil)

        let canDeepAnalyze =
            !alreadyRanForThisDoc &&
            !isLoading &&
            !lastDocumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            purchaseManager.canRunDeepAnalysis()

        return Card("Deeper Analysis", icon: "brain.head.profile", tint: .indigo) {
            VStack(alignment: .leading, spacing: 12) {

                Text("Get a deeper analysis for even more insight.")
                    .font(.subheadline.weight(.semibold))

                Text("This expands the breakdown, surfaces hidden risks, and explains complex clauses in greater detail. May take a few minutes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if alreadyRanForThisDoc {
                    Text("Deeper Analysis already generated for this document.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !purchaseManager.isPro {
                    Text("Uses 1 additional scan.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !purchaseManager.isPro && !purchaseManager.canRunDeepAnalysis() {
                    Text("You need at least 2 scans remaining to run Deeper Analysis.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.25)

                Button {
                    runDeepAnalysis() // we’ll update this next
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                        Text(isLoading ? "Deep analyzing…" : (alreadyRanForThisDoc ? "Deeper Analysis Complete" : "Run Deeper Analysis"))
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canDeepAnalyze)
            }
        }
    }

    private var recentDocuments: some View {
        Card("Recent documents", icon: "clock.fill", tint: .gray) {

            // 1) Recents
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

            // 2) Saved documents (CoreData)
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
                        for doc in savedDocs { context.delete(doc) }
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

    // MARK: - PDF flow

    @MainActor
    private func handleImportedPDF(url: URL) async {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let images = try renderPDF(url: url, maxPages: 12)
            guard !images.isEmpty else {
                errorMessage = "That PDF didn’t contain any renderable pages."
                return
            }

            analysisTask?.cancel()
            analysisTask = Task { await handleScan(images: images) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum PDFRenderError: LocalizedError {
        case couldNotOpen
        case noPages

        var errorDescription: String? {
            switch self {
            case .couldNotOpen: return "Couldn’t open that PDF."
            case .noPages: return "That PDF has no pages."
            }
        }
    }

    private func renderPDF(url: URL, maxPages: Int) throws -> [UIImage] {
        guard let pdf = PDFDocument(url: url) else { throw PDFRenderError.couldNotOpen }
        guard pdf.pageCount > 0 else { throw PDFRenderError.noPages }

        let count = min(pdf.pageCount, maxPages)
        var images: [UIImage] = []
        images.reserveCapacity(count)

        for index in 0..<count {
            guard let page = pdf.page(at: index) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: size))

                ctx.cgContext.saveGState()
                ctx.cgContext.scaleBy(x: scale, y: scale)
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }

            images.append(img)
        }

        return images
    }

    // MARK: - Cancel

    @MainActor
    private func cancelCurrentAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        progressModel.stop()
        isLoading = false
    }
    
    private func docHash(_ text: String) -> String {
        // quick + stable enough for gating; if you want SHA256, you can reuse your SaveAnalysisCard helper
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).hashValue)
    }

    // MARK: - Unified flow (Camera images OR PDF-rendered images)

    @MainActor
    private func handleScan(images: [UIImage]) async {
        isLoading = true
        errorMessage = nil
        analysisResult = nil
        lastDocumentText = ""
        lightingWarning = nil
        showDimLightAlert = false
        deepAnalysisResult = nil
        deepAnalysisSourceHash = nil

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

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 30 else {
                progressModel.stop()
                errorMessage = "Scanned text is too short to analyze. Try scanning again with better lighting."
                return
            }

            lastDocumentText = trimmed
            progressModel.moveTo(cap: 0.99)

            // ✅ creep while waiting on network (keeps UI alive)
            progressModel.startCreep(to: 1.00)

            try Task.checkCancellation()

            let result = try await apiClient.analyzeDocument(text: trimmed, detailLevel: .short)

            // ✅ stop creep once we have a result
            progressModel.stopCreep()

            try Task.checkCancellation()

            analysisResult = result
            recents.add(fullText: trimmed, analysis: result)
            progressModel.finishAndDismiss()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // Consume scan credit ONLY after successful analysis
            purchaseManager.consumeFreeScanIfNeeded()

        } catch is CancellationError {
            progressModel.stopCreep()
            progressModel.stop()
            return
        } catch {
            progressModel.stopCreep()
            progressModel.stop()
            errorMessage = error.localizedDescription
            print("❌ Flow failed:", error)
        }
    }
    
    @MainActor
    private func runDeepAnalysis() {
        guard !isLoading else { return }
        guard !lastDocumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // ✅ Hard gate
        guard purchaseManager.canRunDeepAnalysis() else {
            // Choose your behavior: show paywall or show a friendly error
            if purchaseManager.isPro {
                errorMessage = "Unable to run Deeper Analysis right now."
            } else {
                errorMessage = "Deeper Analysis uses 1 additional scan. You need at least 2 scans remaining."
                showPaywall = true // optional: send them to paywall
            }
            return
        }

        analysisTask?.cancel()
        purchaseManager.lastErrorMessage = nil

        analysisTask = Task { @MainActor in
            isLoading = true
            errorMessage = nil

            progressModel.start()
            progressModel.moveTo(cap: 0.25)

            defer {
                progressModel.stopCreep()
                isLoading = false
            }

            do {
                try Task.checkCancellation()

                progressModel.moveTo(cap: 0.55)
                progressModel.startCreep(to: 0.99)

                let deep = try await apiClient.analyzeDocument(text: lastDocumentText, detailLevel: .long)

                try Task.checkCancellation()

                progressModel.stopCreep()

                analysisResult = deep
                deepAnalysisResult = deep
                deepAnalysisSourceHash = docHash(lastDocumentText)

                recents.add(fullText: lastDocumentText, analysis: deep)

                progressModel.finishAndDismiss()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // ✅ Consume the *extra* deep-analysis scan only after success
                purchaseManager.consumeDeepAnalysisScanIfNeeded()

            } catch is CancellationError {
                progressModel.stopCreep()
                progressModel.stop()
            } catch {
                progressModel.stopCreep()
                progressModel.stop()
                errorMessage = error.localizedDescription
            }
        }
    }



}

// MARK: - Local subviews

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
