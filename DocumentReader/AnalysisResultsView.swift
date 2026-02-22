
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
    
    @State private var copiedToast: String?
    
    // Expand state
    @State private var expandedRightIDs: Set<String> = []
    @State private var expandedBulletIDs: Set<String> = []
    
    // MARK: - Keys
    
    private func rightKey(partyId: UUID, rightId: UUID) -> String {
        "\(partyId.uuidString)|\(rightId.uuidString)"
    }
    
    private func bulletKey(partyId: UUID, section: String, bulletId: UUID) -> String {
        "\(partyId.uuidString)|\(section)|\(bulletId.uuidString)"
    }
    
    private func isRightExpanded(partyId: UUID, rightId: UUID) -> Bool {
        expandedRightIDs.contains(rightKey(partyId: partyId, rightId: rightId))
    }
    
    private func toggleRight(partyId: UUID, rightId: UUID) {
        let key = rightKey(partyId: partyId, rightId: rightId)
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedRightIDs.contains(key) {
                expandedRightIDs.remove(key)
            } else {
                expandedRightIDs.insert(key)
            }
        }
    }
    
    private func isBulletExpanded(partyId: UUID, section: String, bulletId: UUID) -> Bool {
        expandedBulletIDs.contains(bulletKey(partyId: partyId, section: section, bulletId: bulletId))
    }
    
    private func toggleBullet(partyId: UUID, section: String, bulletId: UUID) {
        let key = bulletKey(partyId: partyId, section: section, bulletId: bulletId)
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedBulletIDs.contains(key) {
                expandedBulletIDs.remove(key)
            } else {
                expandedBulletIDs.insert(key)
            }
        }
    }
    
    private func summaryParagraphs(from raw: String?) -> [String] {
        let s = (raw ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !s.isEmpty else { return [] }
        
        // Respect real paragraph breaks if they exist
        let alreadyParagraphs = s
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if alreadyParagraphs.count >= 2 { return alreadyParagraphs }
        
        // Sentence-based split (simple)
        let normalized = s.replacingOccurrences(of: "\n", with: " ")
        
        let rawPieces = normalized.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Re-add punctuation as periods (good enough for UI)
        let sentences = rawPieces.map { $0 + "." }
        
        // If the model gave us multiple sentences, group them
        if sentences.count >= 3 {
            var paras: [String] = []
            var current: [String] = []
            
            for (idx, sentence) in sentences.enumerated() {
                current.append(sentence)
                
                let shouldBreak =
                current.count == 3 ||
                (current.count >= 2 && idx == sentences.count - 1)
                
                if shouldBreak {
                    paras.append(current.joined(separator: " "))
                    current.removeAll()
                }
            }
            if !current.isEmpty { paras.append(current.joined(separator: " ")) }
            return paras
        }
        
        // ✅ Fallback: long “single sentence” summaries (your screenshot case)
        // Break into readable chunks by length, preferring comma boundaries.
        let target = 220  // tune 180–260 to taste
        var paras: [String] = []
        var buffer = ""
        
        // split by comma+space as soft clauses
        let clauses = normalized.components(separatedBy: ", ")
        
        for clause in clauses {
            let piece = buffer.isEmpty ? clause : (buffer + ", " + clause)
            
            if piece.count >= target {
                paras.append(piece.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = ""
            } else {
                buffer = piece
            }
        }
        
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paras.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // If we somehow ended up with just one, return original
        return paras.count >= 2 ? paras : [normalized]
    }
    
    
    // MARK: - Export
    
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
        
        if let simple = result.simpleEnglish,
           !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        
        if let analogy = result.eli5Analogy,
           !analogy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("ELI5 Analogy:")
            parts.append(analogy)
            parts.append("")
        }
        
        if let parties = result.partyAnalysis, !parties.isEmpty {
            parts.append("Benefits, liabilities, possible penalties, and catches by party:")
            
            func exportBullets(_ title: String, _ bullets: [CitedBullet]) {
                guard !bullets.isEmpty else { return }
                parts.append("  \(title):")
                for b in bullets {
                    parts.append("  - \(b.text)")
                    if !b.citations.isEmpty {
                        parts.append("    Citations:")
                        for c in b.citations {
                            parts.append("    - \(c.source)\(c.quote.map { " — “\($0)”" } ?? "")")
                        }
                    }
                }
            }
            
            for p in parties {
                parts.append("\n\(p.party):")
                exportBullets("Benefits", p.benefits)
                exportBullets("Liabilities / obligations", p.liabilities)
                exportBullets("Possible penalties / consequences", p.possiblePenalties)
                exportBullets("Catches / gotchas", p.catches)
                
                if !p.rights.isEmpty {
                    parts.append("  Rights:")
                    for r in p.rights {
                        parts.append("  - \(r.right): \(r.details)")
                        if !r.citations.isEmpty {
                            parts.append("    Citations:")
                            for c in r.citations {
                                parts.append("    - \(c.source)\(c.quote.map { " — “\($0)”" } ?? "")")
                            }
                        }
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
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    
                    if let paras = result.analysisParagraphs, !paras.isEmpty {
                        detailedAnalysisCard(paras)
                    }
                    
                    if let simple = result.simpleEnglish,
                       !simple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        simpleEnglishCard(simple)
                    }
                    
                    if let eli5 = result.eli5Paragraphs, eli5.count >= 2 {
                        eli5Card(eli5)
                    }
                    
                    if let parties = result.partyAnalysis, !parties.isEmpty {
                        partyAnalysisCard(parties)
                    }
                    
                    if let wb = result.whoBenefitsMost {
                        whoBenefitsMostCard(wb)
                    }
                    
                    keyInfoCard
                    
                    if let drafts = result.drafts?.allDrafts, !drafts.isEmpty {
                        draftsCard(drafts)
                    }
                    
                    exportCard
                    
                    SaveAnalysisCard(
                        canSave: canSave,
                        result: result,
                        documentText: documentText,
                        exportText: exportText
                    )
                    
                    if let lim = result.limitations, !lim.isEmpty {
                        limitationsCard(lim)
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
    
    // MARK: - Cards (broken into smaller subviews to fix type-check issues)
    
    private var summaryCard: some View {
        Card("Summary") {
            VStack(alignment: .leading, spacing: 10) {
                
                let paras = summaryParagraphs(from: result.summaryPlain)
                
                if paras.isEmpty {
                    Text("No summary returned.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(paras.indices, id: \.self) { i in
                        Text(paras[i])
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineSpacing(2)
                    }
                }
            }
            
            if let wb = result.whoBenefitsMost {
                Divider().opacity(0.25)
                Text("Likely benefits most: \(wb.party) (\(Int(wb.confidence * 100))%)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }


private func detailedAnalysisCard(_ paras: [String]) -> some View {
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

private func simpleEnglishCard(_ text: String) -> some View {
    Card("Explanation in simple English") {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
    }
}

private func eli5Card(_ eli5: [String]) -> some View {
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

private func partyAnalysisCard(_ parties: [PartyBenefitsLiabilities]) -> some View {
    Card("Benefits, liabilities, penalties & catches") {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(parties) { p in
                PartyBlockView(
                    party: p,
                    isBulletExpanded: { section, bulletId in
                        isBulletExpanded(partyId: p.id, section: section, bulletId: bulletId)
                    },
                    toggleBullet: { section, bulletId in
                        toggleBullet(partyId: p.id, section: section, bulletId: bulletId)
                    },
                    isRightExpanded: { rightId in
                        isRightExpanded(partyId: p.id, rightId: rightId)
                    },
                    toggleRight: { rightId in
                        toggleRight(partyId: p.id, rightId: rightId)
                    }
                )
                
                Divider().opacity(0.18)
            }
        }
    }
}

private func whoBenefitsMostCard(_ wb: WhoBenefitsMost) -> some View {
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

private var keyInfoCard: some View {
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
}

private func draftsCard(_ drafts: [(title: String, text: String)]) -> some View {
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

private var exportCard: some View {
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
}

private func limitationsCard(_ lim: [String]) -> some View {
    Card("Limitations") {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lim, id: \.self) { Text("• \( $0 )") }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Helpers

private func row(_ k: String, _ v: String) -> some View {
    HStack {
        Text(k).foregroundStyle(.secondary)
        Spacer()
        Text(v).fontWeight(.semibold)
    }
    .font(.subheadline)
}
}

// MARK: - Party block extracted (fixes “unable to type-check”)

private struct PartyBlockView: View {
    let party: PartyBenefitsLiabilities
    
    let isBulletExpanded: (_ section: String, _ bulletId: UUID) -> Bool
    let toggleBullet: (_ section: String, _ bulletId: UUID) -> Void
    
    let isRightExpanded: (_ rightId: UUID) -> Bool
    let toggleRight: (_ rightId: UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(party.roleTitle.isEmpty ? "Party" : party.roleTitle)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(party.party.isEmpty ? "Unknown party" : party.party)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ThickDivider()
            
            if !party.benefits.isEmpty {
                sectionTitle("Benefits")
                citedBullets(party.benefits, section: "benefits")
                ThickDivider()
            }
            
            if !party.liabilities.isEmpty {
                sectionTitle("Liabilities / obligations")
                citedBullets(party.liabilities, section: "liabilities")
                ThickDivider()
            }
            
            if !party.possiblePenalties.isEmpty {
                sectionTitle("Possible penalties / consequences")
                citedBullets(party.possiblePenalties, section: "possible_penalties")
                ThickDivider()
            }
            
            if !party.catches.isEmpty {
                sectionTitle("Catches / gotchas")
                citedBullets(party.catches, section: "catches")
                ThickDivider()
            }
            
            if !party.rights.isEmpty {
                sectionTitle("Rights")
                rightsList(party.rights)
                ThickDivider()
            }
        }
        .padding(.vertical, 6)
    }
    
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }
    
    private func citedBullets(_ items: [CitedBullet], section: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { b in
                CitedBulletRow(
                    bullet: b,
                    isExpanded: isBulletExpanded(section, b.id),
                    onToggle: { toggleBullet(section, b.id) }
                )
            }
        }
    }
    
    private func rightsList(_ rights: [PartyRight]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rights) { r in
                RightRow(
                    right: r,
                    isExpanded: isRightExpanded(r.id),
                    onToggle: { toggleRight(r.id) }
                )
                Divider().opacity(0.18)
            }
        }
    }
}


// MARK: - Rows extracted (tappable citations)

private struct CitedBulletRow: View {
    let bullet: CitedBullet
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Text("• \(bullet.text)")
                        .foregroundStyle(.secondary) // ✅ was .secondary
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !bullet.citations.isEmpty {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    } else {
                        // Optional: show a subtle “no citation” indicator if you want
                        EmptyView()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            //  .disabled(bullet.citations.isEmpty)
            
            if isExpanded, !bullet.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(bullet.citations) { c in
                        Text("↳ \(c.source)\(c.quote.map { " — “\($0)”" } ?? "")")
                            .font(.footnote)
                            .foregroundStyle(.secondary.opacity(0.9))
                    }
                }
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct RightRow: View {
    let right: PartyRight
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Text("• \(right.right): \(right.details)")
                        .foregroundStyle(.secondary) // ✅ was .secondary
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !right.citations.isEmpty {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(right.citations.isEmpty)
            
            if isExpanded, !right.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(right.citations) { c in
                        Text("↳ \(c.source)\(c.quote.map { " — “\($0)”" } ?? "")")
                            .font(.footnote)
                            .foregroundStyle(.secondary.opacity(0.9))
                    }
                }
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Dividers (your existing ones)

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

// MARK: - Keyboard helpers (your existing ones)

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

