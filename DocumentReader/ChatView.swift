import SwiftUI
import UIKit

struct ChatView: View {
    let conversationId: String
    let documentText: String
    let suggestedQuestions: [String]

    struct PDFVersion: Identifiable, Equatable {
        let id = UUID()
        let createdAt: Date
        let title: String

        let pdfURL: URL
        let analysisURL: URL
        let zipURL: URL?

        let draft: PDFDraft
    }

    struct ChatUIMessage: Identifiable, Equatable {
        let id: UUID
        let role: String      // "system" | "user" | "assistant"
        let content: String
        let isThinking: Bool

        init(id: UUID = UUID(), role: String, content: String, isThinking: Bool = false) {
            self.id = id
            self.role = role
            self.content = content
            self.isThinking = isThinking
        }
    }

    @State private var messages: [ChatUIMessage] = []
    @State private var input: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    @State private var pdfVersions: [PDFVersion] = []
    @State private var activePDFVersion: PDFVersion?
    @State private var showPDFTools: Bool = false

    private let api = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        if let v = activePDFVersion {
                            pdfExportBar(version: v)

                            DisclosureGroup(isExpanded: $showPDFTools) {
                                VStack(spacing: 12) {
                                    pdfImproveActions
                                    pdfVersionsList
                                }
                                .padding(.top, 8)
                            } label: {
                                Text("PDF tools")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        if !suggestedQuestions.isEmpty && messages.count <= 2 {
                            suggestionsRow
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages.filter { $0.role != "system" }) { msg in
                                bubble(msg).id(msg.id)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.vertical, 14)
                }
                .onChange(of: messages.count) { _ in
                    guard let last = messages.last(where: { $0.role != "system" }) else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            composer
                .padding(.horizontal, DS.pagePadding)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .background(ScreenBackground())
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnTap()
        .polishedNavBar()
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            bootstrapMessagesIfNeeded()
            loadExistingPDFVersions()
        }
    }

    // MARK: - Bootstrap

    private func bootstrapMessagesIfNeeded() {
        if messages.isEmpty {
            messages.append(.init(
                role: "system",
                content: """
You are a document-focused legal information assistant.

Rules:
- Only answer questions that relate to the provided document text and its legal subject matter.
- You MAY help draft letters/emails that reference or negotiate terms found in the document (rent, fees, deposit, notice periods, deadlines, termination, etc.).
- If the user requests a PDF letter, you MUST draft the actual letter content (not just summarize, not just restate the request, and do not ask clarifying questions). Use placeholders like [Landlord Name], [Address], [Date] if needed.
- If the user asks for something unrelated to the document, refuse briefly and ask them to ask about the document.
- Do not provide legal advice; provide general information and drafting help.
"""
            ))

            messages.append(.init(
                role: "assistant",
                content: "Ask me questions about this document. If you want, ask: “Draft a PDF response letter about this document.” (Not legal advice.)"
            ))
        }
    }

    // MARK: - Load existing PDFs

    private func loadExistingPDFVersions() {
        let bundles = ArtifactStore.listBundles(conversationId: conversationId)
        guard !bundles.isEmpty else { return }

        var loaded: [PDFVersion] = []
        loaded.reserveCapacity(bundles.count)

        for b in bundles {
            do {
                let pdfURL = try ArtifactStore.resolvePDFURL(conversationId: conversationId, pdfFilename: b.pdfFilename)
                let analysisURL = try ArtifactStore.resolveAnalysisURL(conversationId: conversationId, analysisFilename: b.analysisFilename)

                var zipURL: URL? = nil
                if let z = b.zipFilename {
                    zipURL = try ArtifactStore.resolveZipURL(conversationId: conversationId, zipFilename: z)
                }

                let data = try Data(contentsOf: analysisURL)
                let payload = try JSONDecoder.iso8601.decode(SavedPDFArtifact.self, from: data)

                loaded.append(PDFVersion(
                    createdAt: b.createdAt,
                    title: b.title,
                    pdfURL: pdfURL,
                    analysisURL: analysisURL,
                    zipURL: zipURL,
                    draft: payload.draft
                ))

            } catch {
                // If one entry fails, skip it rather than breaking the whole list.
                continue
            }
        }

        if !loaded.isEmpty {
            pdfVersions = loaded.sorted(by: { $0.createdAt < $1.createdAt })
            activePDFVersion = pdfVersions.last
        }
    }

    // MARK: - UI

    private var header: some View {
        Card(nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Context loaded")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(documentText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 12)
    }

    private func pdfExportBar(version: PDFVersion) -> some View {
        Card("PDF Draft Ready") {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext")

                VStack(alignment: .leading, spacing: 2) {
                    Text(version.title)
                        .font(.subheadline.weight(.semibold))

                    Text("Version \(pdfVersions.firstIndex(of: version).map { $0 + 1 } ?? 1) • \(version.createdAt, style: .time)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShareLink(item: version.pdfURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var pdfImproveActions: some View {
        Card("Improve this PDF") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await improvePDF(style: "Make it more polite and professional. Keep it concise.") }
                } label: {
                    Label("Make it more professional", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(activePDFVersion == nil || isSending)

                Button {
                    Task { await improvePDF(style: "Add stronger negotiation language and persuasive reasons, but stay respectful.") }
                } label: {
                    Label("Make it more persuasive", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
                .disabled(activePDFVersion == nil || isSending)

                Button {
                    Task { await improvePDF(style: "Make it shorter and clearer. Remove fluff.") }
                } label: {
                    Label("Shorten & clarify", systemImage: "scissors")
                }
                .buttonStyle(.bordered)
                .disabled(activePDFVersion == nil || isSending)

                Text("Each improvement creates a new saved PDF version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pdfVersionsList: some View {
        Card("Draft versions") {
            VStack(spacing: 10) {
                ForEach(pdfVersions.indices.reversed(), id: \.self) { idx in
                    let v = pdfVersions[idx]
                    Button {
                        activePDFVersion = v
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Version \(idx + 1)")
                                    .font(.subheadline.weight(.semibold))
                                Text(v.title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if activePDFVersion?.id == v.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if idx != pdfVersions.indices.first {
                        Divider().opacity(0.25)
                    }
                }
            }
        }
    }

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(suggestedQuestions.prefix(8), id: \.self) { q in
                    Button {
                        input = q
                        Task { await send() }
                    } label: {
                        Text(q)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSending)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if input.isEmpty {
                    Text("Ask a document question…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                }

                TextField("", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                Task { await send() }
            } label: {
                Image(systemName: isSending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func bubble(_ msg: ChatUIMessage) -> some View {
        HStack(alignment: .bottom) {
            if msg.role == "assistant" {
                VStack(alignment: .leading, spacing: 6) {
                    if msg.isThinking {
                        ThinkingDots().padding(.vertical, 6)
                    } else {
                        SelectableText(text: msg.content, textColor: .label)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)

                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)

                SelectableText(text: msg.content, textColor: .white)
                    .padding(12)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            }
        }
    }

    // MARK: - Send

    @MainActor
    private func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        input = ""
        isSending = true
        errorMessage = nil

        messages.append(.init(role: "user", content: trimmed))

        let thinkingId = UUID()
        messages.append(.init(id: thinkingId, role: "assistant", content: "", isThinking: true))

        do {
            let wire = messages
                .filter { !$0.isThinking }
                .map { APIClient.ChatWireMessage(role: $0.role, content: $0.content) }

            var resp = try await api.chatAboutDocument(documentText: documentText, messages: wire)

            if let draft = resp.pdfDraft, isBadPDFDraft(draft, userRequest: trimmed) {
                let retryWire = wire + [
                    .init(role: "user", content: """
Draft the actual letter now as a PDF-ready draft.
- Do NOT ask clarifying questions.
- Do NOT restate the request.
- Include the full letter with a polite tone and placeholders if needed.
""")
                ]
                resp = try await api.chatAboutDocument(documentText: documentText, messages: retryWire)
            }

            var assistantReply = resp.reply

            if let draft = resp.pdfDraft {
                _ = try persistNewPDFVersion(from: draft, assistantReply: resp.reply)

                // ✅ FIX: if the PDF was created, always show success in the chat.
                assistantReply = "✅ PDF created. Use **PDF Draft Ready** above to share/export. (Not legal advice.)"
            }

            if let idx = messages.firstIndex(where: { $0.id == thinkingId }) {
                messages[idx] = .init(role: "assistant", content: assistantReply)
            } else {
                messages.append(.init(role: "assistant", content: assistantReply))
            }

        } catch {
            if let idx = messages.firstIndex(where: { $0.id == thinkingId }) {
                messages.remove(at: idx)
            }
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    // MARK: - Improve PDF

    @MainActor
    private func improvePDF(style: String) async {
        guard activePDFVersion != nil else { return }

        isSending = true
        errorMessage = nil

        let thinkingId = UUID()
        messages.append(.init(id: thinkingId, role: "assistant", content: "", isThinking: true))

        do {
            let wire = messages
                .filter { !$0.isThinking }
                .map { APIClient.ChatWireMessage(role: $0.role, content: $0.content) }

            let revisionPrompt = """
Revise the last drafted letter with these instructions:
\(style)

Return an updated pdfDraft with the full revised letter.
Do NOT ask clarifying questions.
Do NOT restate the user’s request.
"""

            let resp = try await api.chatAboutDocument(documentText: documentText, messages: wire + [
                .init(role: "user", content: revisionPrompt)
            ])

            guard let newDraft = resp.pdfDraft else {
                throw NSError(domain: "PDFImprove", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No revised PDF draft was returned."
                ])
            }

            _ = try persistNewPDFVersion(from: newDraft, assistantReply: resp.reply)

            let reply = "✅ Updated PDF created (new version). Use **PDF Draft Ready** above to share/export. (Not legal advice.)"

            if let idx = messages.firstIndex(where: { $0.id == thinkingId }) {
                messages[idx] = .init(role: "assistant", content: reply)
            } else {
                messages.append(.init(role: "assistant", content: reply))
            }

        } catch {
            if let idx = messages.firstIndex(where: { $0.id == thinkingId }) {
                messages.remove(at: idx)
            }
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    // MARK: - Persist PDF + JSON via ArtifactStore

    private func persistNewPDFVersion(from draft: PDFDraft, assistantReply: String) throws -> PDFVersion {
        let hasMeaningfulText =
            (draft.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || (draft.sections ?? []).contains(where: {
                !($0.heading ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !($0.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })

        guard hasMeaningfulText else {
            throw NSError(domain: "PDFDraft", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The PDF draft came back empty."
            ])
        }

        let pdfData = try PDFExporter.makePDF(draft: draft)

        let payload = SavedPDFArtifact(
            createdAt: Date(),
            title: (draft.title?.isEmpty == false ? draft.title! : "Draft-Response"),
            draft: draft,
            assistantReply: assistantReply
        )
        let analysisJSON = try JSONEncoder.iso8601.encode(payload)

        let versionNumber = pdfVersions.count + 1
        let title = payload.title

        // ✅ FIX: no makeZip argument here (matches ArtifactStore.saveBundle signature)
        let entry = try ArtifactStore.saveBundle(
            conversationId: conversationId,
            versionNumber: versionNumber,
            title: title,
            pdfData: pdfData,
            analysisJSON: analysisJSON,
            zipData: nil
        )

        let pdfURL = try ArtifactStore.resolvePDFURL(conversationId: conversationId, pdfFilename: entry.pdfFilename)
        let analysisURL = try ArtifactStore.resolveAnalysisURL(conversationId: conversationId, analysisFilename: entry.analysisFilename)
        var zipURL: URL? = nil
        if let z = entry.zipFilename {
            zipURL = try ArtifactStore.resolveZipURL(conversationId: conversationId, zipFilename: z)
        }

        let v = PDFVersion(
            createdAt: entry.createdAt,
            title: entry.title,
            pdfURL: pdfURL,
            analysisURL: analysisURL,
            zipURL: zipURL,
            draft: draft
        )

        pdfVersions.append(v)
        activePDFVersion = v
        return v
    }

    private func isBadPDFDraft(_ draft: PDFDraft, userRequest: String) -> Bool {
        let title = (draft.title ?? "").lowercased()
        let allText = ([title] + (draft.sections ?? []).flatMap { [($0.heading ?? ""), ($0.body ?? "")] })
            .joined(separator: "\n")
            .lowercased()

        let badMarkers = [
            "questions / clarifications",
            "what i'm responding to",
            "please confirm",
            "intended to",
            "requested adjustments (if applicable)"
        ]
        if badMarkers.contains(where: { allText.contains($0) }) { return true }

        let req = userRequest.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if req.count > 20, allText.contains(req), (draft.sections?.count ?? 0) <= 2 {
            return true
        }

        let bodyLen = (draft.sections ?? []).map { ($0.body ?? "").count }.reduce(0, +)
        return bodyLen < 80
    }
}

// MARK: - PDF artifact JSON payload

private struct SavedPDFArtifact: Codable {
    let createdAt: Date
    let title: String
    let draft: PDFDraft
    let assistantReply: String
}

// MARK: - Thinking dots

private struct ThinkingDots: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            dot(active: phase == 0)
            dot(active: phase == 1)
            dot(active: phase == 2)
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = (phase + 1) % 3
            }
        }
    }

    private func dot(active: Bool) -> some View {
        Circle()
            .frame(width: 7, height: 7)
            .opacity(active ? 1.0 : 0.25)
    }
}

// MARK: - Selectable text (no cut-off + supports Select/Select All/Copy)

struct SelectableText: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor

    func makeUIView(context: Context) -> IntrinsicTextView {
        let tv = IntrinsicTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.dataDetectorTypes = []

        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.widthTracksTextView = true

        tv.adjustsFontForContentSizeCategory = true
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        tv.font = font
        tv.textColor = textColor
        return tv
    }

    func updateUIView(_ uiView: IntrinsicTextView, context: Context) {
        uiView.font = font
        uiView.textColor = textColor
        uiView.text = text

        uiView.invalidateIntrinsicContentSize()
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }
}

/// A UITextView that reports correct intrinsic height.
final class IntrinsicTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let size = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - ISO8601 Codable helpers

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
