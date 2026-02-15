//
//  TermsAndConditionsView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/18/26.
//

import SwiftUI
import UIKit

struct TermsAndConditionsView: View {
    let onAccept: () -> Void

    @State private var termsAgreed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 14) {
                Text("Terms & Conditions")
                    .font(.title2.weight(.bold))
                    .padding(.top, 18)

                Text("Please review and accept to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Card("Important", icon: "shield.lefthalf.filled", tint: .yellow) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Not Legal Advice").font(.headline)
                            Text("""
This app provides general informational content and automated summaries. It is not a substitute for advice from a qualified attorney.

No attorney-client relationship is created by using this app, its analysis, chat responses, or generated documents.
""")
                            Divider().opacity(0.25)

                            Text("Limitation of Liability").font(.headline)
                            Text("""
To the maximum extent permitted by law, you agree that the app and its creators are not liable for any damages, losses, claims, or legal consequences arising from your use of the app, including reliance on analysis, summaries, or responses.

You are responsible for verifying information and obtaining professional advice before making legal, financial, or other decisions.
""")
                            Divider().opacity(0.25)

                            Text("Use at Your Own Risk").font(.headline)
                            Text("""
Document OCR and interpretation may be inaccurate. You agree to use the app at your own risk and confirm that you will independently review any important content.
""")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: 320)
                }
                .padding(.horizontal, DS.pagePadding)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    termsAgreed = true

                    // Start dismissal immediately
                    dismiss()

                    // Let the dismiss transition begin, then mark accepted
                    Task { @MainActor in
                        await Task.yield()
                        onAccept()
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("I Agree").fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, DS.pagePadding)
                .padding(.bottom, 18)
                .disabled(termsAgreed)
            }
        }
    }
}
