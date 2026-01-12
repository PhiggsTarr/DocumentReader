import SwiftUI

struct ChatView: View {
    let documentText: String
    let suggestedQuestions: [String]

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

    // ✅ NEW
    @State private var lastPDFDraft: PDFDraft?
    @State private var lastPDFURL: URL?

    private let api = APIClient()

    var body: some View {
        VStack(spacing: 0) {
            header

            if let url = lastPDFURL {
                pdfExportBar(pdfURL: url)
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.top, 10)
            }

            if !suggestedQuestions.isEmpty && messages.count <= 2 {
                suggestionsRow
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.top, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.filter { $0.role != "system" }) { msg in
                            bubble(msg).id(msg.id)
                        }
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
            if messages.isEmpty {
                messages.append(.init(
                    role: "system",
                    content: """
You are a document-focused legal information assistant.
Rules:
- Only answer questions that relate to the provided document text and its legal subject matter.
- If the user asks unrelated questions, refuse briefly and ask them to ask about the document.
- Do not provide legal advice; provide general information.
"""
                ))

                messages.append(.init(
                    role: "assistant",
                    content: "Ask me questions about this document. If you want, ask: “Draft a PDF response letter about this document.” (Not legal advice.)"
                ))
            }
        }
    }

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

    private func pdfExportBar(pdfURL: URL) -> some View {
        Card("PDF Draft Ready") {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext")
                Text("Export the drafted response as a PDF")
                    .font(.subheadline)
                Spacer()
                ShareLink(item: pdfURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
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
                        Text(msg.content)
                    }
                }
                .font(.body)
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)

                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)

                Text(msg.content)
                    .font(.body)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            }
        }
    }

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
            let wireMessages: [APIClient.ChatWireMessage] = messages
                .filter { !$0.isThinking }
                .map { APIClient.ChatWireMessage(role: $0.role, content: $0.content) }

            let resp = try await api.chatAboutDocument(documentText: documentText, messages: wireMessages)

            // Replace thinking bubble with reply
            if let idx = messages.firstIndex(where: { $0.id == thinkingId }) {
                messages[idx] = .init(role: "assistant", content: resp.reply)
            } else {
                messages.append(.init(role: "assistant", content: resp.reply))
            }

            // ✅ If a PDF draft came back, render a PDF file and show ShareLink
            if let draft = resp.pdfDraft {
                lastPDFDraft = draft
                do {
                    let url = try PDFRenderer.render(draft: draft)
                    lastPDFURL = url
                } catch {
                    errorMessage = "Failed to render PDF: \(error.localizedDescription)"
                }
            }

        } catch {
            if let idx = messages.firstIndex(where: { $0.id == thinkingId }) {
                messages.remove(at: idx)
            }
            errorMessage = error.localizedDescription
        }

        isSending = false
    }
}

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
