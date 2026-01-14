//
//  AnalysisResultView.swift
//  DocumentReader
//

import SwiftUI
import UIKit
import CryptoKit

struct AnalysisResultView: View {
    let result: DocumentAnalyzeResponse
    let documentText: String
    let canSave: Bool
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var saveToast: String?
    @Environment(\.managedObjectContext) private var moc
    @StateObject private var store = DocumentStore()
    @State private var copiedToast: String?
    
    private func saveToHistory() {
        do {
            try store.saveDocument(
                title: result.docType ?? "Document",
                documentText: documentText,
                fileURL: nil, // or URL if you saved the PDF to disk
                analysis: result,
                exportText: exportText
                
            )
        } catch {
            print("Save failed: \(error)")
        }
    }

    private var exportText: String {
        var parts: [String] = []
        parts.append("Document type: \(result.docType ?? "Unknown")")
        if let c = result.confidence { parts.append("Confidence: \(String(format: "%.2f", c))") }
        parts.append("")

        if let wb = result.whoBenefitsMost {
            parts.append("Who benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
            if !wb.reasons.isEmpty {
                parts.append("Reasons:")
                parts.append(contentsOf: wb.reasons.map { "- \($0)" })
            }
            parts.append("")
        }

        parts.append("Summary:")
        parts.append(result.summaryPlain ?? "(none)")
        parts.append("")

        if let simple = result.simpleEnglish, !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Explain it to me in plain simple English:")
            parts.append(simple)
            parts.append("")
        }

        if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
            parts.append("Explain it to me like I'm 5:")
            parts.append(eli5[0])
            parts.append("")
            parts.append(eli5[1])
            parts.append("")
        }

        if let analogy = result.eli5Analogy, !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("ELI5 Analogy:")
            parts.append(analogy)
            parts.append("")
        }

        if let parties = result.partyAnalysis, !parties.isEmpty {
            parts.append("Benefits, liabilities, possible penalties, and catches by party:")
            for p in parties {
                parts.append("\n\(p.party):")

                if !p.benefits.isEmpty {
                    parts.append("  Benefits:")
                    parts.append(contentsOf: p.benefits.map { "  - \($0)" })
                }

                if !p.liabilities.isEmpty {
                    parts.append("  Liabilities / obligations:")
                    parts.append(contentsOf: p.liabilities.map { "  - \($0)" })
                }

                if !p.possiblePenalties.isEmpty {
                    parts.append("  Possible penalties / consequences:")
                    parts.append(contentsOf: p.possiblePenalties.map { "  - \($0)" })
                }

                if !p.catches.isEmpty {
                    parts.append("  Catches / gotchas:")
                    parts.append(contentsOf: p.catches.map { "  - \($0)" })
                }

                if !p.rights.isEmpty {
                    parts.append("  Rights:")
                    for r in p.rights {
                        parts.append("  - \(r.right): \(r.details)")
                    }
                }
            }
            parts.append("")
        }

        if let paras = result.analysisParagraphs, !paras.isEmpty {
            parts.append("Detailed analysis:")
            parts.append(contentsOf: paras.map { "- \($0)" })
            parts.append("")
        }

        if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
            parts.append("Drafts:")
            for d in drafts {
                parts.append("\n\(d.title):\n\(d.text)\n")
            }
        }

        if let lim = result.limitations, !lim.isEmpty {
            parts.append("\nLimitations:")
            parts.append(contentsOf: lim.map { "- \($0)" })
        }

        return parts.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            ScreenBackground()


            ScrollView {
//                Button {
//                    saveToHistory()
//                } label: {
//                    Label("Save", systemImage: "tray.and.arrow.down")
//                }
//                .buttonStyle(.bordered)
                VStack(spacing: 14) {

                    Card("Summary") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(result.summaryPlain ?? "No summary returned.")
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let wb = result.whoBenefitsMost {
                                Divider().opacity(0.25)
                                Text("Likely benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let paras = result.analysisParagraphs, !paras.isEmpty {
                        Card("Detailed analysis") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(paras.indices, id: \.self) { i in
                                    Text(paras[i])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if i != paras.count - 1 { Divider().opacity(0.25) }
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    if let simple = result.simpleEnglish,
                       !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Card("Explanation in simple English") {
                            Text(simple)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
                        Card("Explain like I’m 5") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(eli5[0])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Divider().opacity(0.25)

                                Text(eli5[1])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let analogy = result.eli5Analogy,
                                   !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Divider().opacity(0.25)
                                    Text("Analogy")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(analogy)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    if let parties = result.partyAnalysis, !parties.isEmpty {
                        Card("Benefits, liabilities, penalties & catches") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(parties) { p in
                                    VStack(alignment: .leading, spacing: 10) {
                                        ThickDividerTwo()
                                        Text(p.roleTitle.isEmpty ? "Party" : p.roleTitle)
                                            .font(.headline)
                                            .fontWeight(.bold)

                                        Text(p.party.isEmpty ? "Unknown party" : p.party)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        ThickDivider()

                                        if !p.benefits.isEmpty {
                                            sectionTitle("Benefits")
                                            bulletList(p.benefits)
                                            ThickDivider()
                                        }

                                        if !p.liabilities.isEmpty {
                                            sectionTitle("Liabilities / obligations")
                                            bulletList(p.liabilities)
                                            ThickDivider()
                                        }

                                        if !p.possiblePenalties.isEmpty {
                                            sectionTitle("Possible penalties / consequences")
                                            bulletList(p.possiblePenalties)
                                            ThickDivider()
                                        }

                                        if !p.catches.isEmpty {
                                            sectionTitle("Catches / gotchas")
                                            bulletList(p.catches)
                                            ThickDivider()
                                        }

                                        if !p.rights.isEmpty {
                                            sectionTitle("Rights")
                                            ForEach(p.rights) { r in
                                                Text("• \(r.right): \(r.details)")
                                                    .foregroundStyle(.secondary)

                                                if !r.citations.isEmpty {
                                                    ForEach(r.citations.indices, id: \.self) { i in
                                                        let c = r.citations[i]
                                                        Text("↳ \(c.source)\(c.quote.map { " — “\($0)”" } ?? "")")
                                                            .font(.footnote)
                                                            .foregroundStyle(.secondary.opacity(0.85))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let wb = result.whoBenefitsMost {
                        Card("Who benefits most?") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(wb.party)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int(wb.confidence * 100))%")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                if !wb.reasons.isEmpty {
                                    ForEach(wb.reasons, id: \.self) { r in
                                        Text("• \(r)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Card("Key info") {
                        VStack(alignment: .leading, spacing: 10) {
                            row("Type", result.docType ?? "Unknown")
                            if let c = result.confidence {
                                row("Confidence", String(format: "%.2f", c))
                            }
                            if let u = result.urgency?.level {
                                row("Urgency", u)
                            }
                        }
                    }

                    if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
                        Card("Draft letters") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(drafts, id: \.title) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(item.title)
                                                .font(.headline)
                                            Spacer()
                                            Button {
                                                UIPasteboard.general.string = item.text
                                                copiedToast = "Copied: \(item.title)"
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.bordered)
                                        }

                                        Text(item.text)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Divider().opacity(0.25)
                                }
                            }
                        }
                    }

                    Card("Export") {
                        HStack(spacing: 10) {
                            ShareLink(item: exportText) {
                                Label("Share analysis", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                UIPasteboard.general.string = exportText
                                copiedToast = "Copied: Full export"
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    SaveAnalysisCard(canSave: canSave, result: result, documentText: documentText, exportText: exportText)

                    if let lim = result.limitations, !lim.isEmpty {
                        Card("Limitations") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(lim, id: \.self) { Text("• \( $0 )") }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
        .overlay(alignment: .top) {
            if let toast = copiedToast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { copiedToast = nil }
                        }
                    }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text("• \(s)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}


struct ThickDivider: View {
    var body: some View {
        Rectangle()
            .frame(height: 2)
            .foregroundColor(.white.opacity(0.25))
            .padding(.vertical, 4)
    }
}

struct ThickDividerTwo: View {
    var body: some View {
        Rectangle()
            .frame(height: 16)
            .foregroundColor(.white.opacity(0.25))
            .padding(.vertical, 4)
    }
}

struct SaveAnalysisCard: View {
    let canSave: Bool
    let result: DocumentAnalyzeResponse
    let documentText: String
    let exportText: String

    @State private var isSaving = false
    @State private var isSaved = false
    @State private var toast: String?

    // Prefer injecting the store (see notes below). This is OK if DocumentStore is lightweight.
    @StateObject private var store = DocumentStore()

    var body: some View {
        Group {
            if canSave {
                Card("Save") {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSaved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                            Text(isSaved ? "Saved" : (isSaving ? "Saving…" : "Save"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaved || isSaving)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { self.toast = nil }
                        }
                    }
            }
        }
    }
    func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func save() {
        guard !isSaving && !isSaved else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toast = "Already saved"
            return
        }

        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        do {
            let hash = sha256(documentText)

            if let _ = try store.existsDocument(withTextHash: hash) {
                isSaved = true
                isSaving = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast = "Already saved"
                return
            }

            try store.saveDocument(
                title: result.docType ?? "Document",
                documentText: documentText,
                fileURL: nil,
                analysis: result,
                exportText: exportText
            )

            isSaved = true
            isSaving = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toast = "Saved"
        } catch {
            isSaving = false
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            toast = "Save failed: \(error.localizedDescription)"
        }
    }
}



extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder),
                   to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Tap anywhere to dismiss keyboard.
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.dismissKeyboard()
        }
    }
}
