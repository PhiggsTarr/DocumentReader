//
//  PrivacyPolicyView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/18/26.
//

import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {
                    Card("Privacy Policy", icon: "hand.raised.fill", tint: .mint) {
                        VStack(alignment: .leading, spacing: 12) {

                            Text("Summary")
                                .font(.headline)

                            Text("""
We process document text you scan or paste to provide summaries, interpretation, and drafting features. We do not guarantee accuracy. This app provides informational content only and is not legal advice. Use at your own risk.
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("What we collect")
                                .font(.headline)

                            Text("""
- Document text you scan, paste, or chat about
- App usage signals needed to run features (e.g., local saved documents, saved analyses, recent history)
- Purchase status (Pro / entitlement) via Apple StoreKit
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("How we use it")
                                .font(.headline)

                            Text("""
- To analyze and summarize your document text
- To generate draft letters and PDFs you request
- To display and manage your history locally (if you choose to save)
- To determine access to Pro features (StoreKit entitlement)
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("Storage")
                                .font(.headline)

                            Text("""
On-device storage:
- Saved documents and saved analyses are stored locally on your device using Core Data (only if you choose to save).
- PDFs generated in chat are stored as local files on your device so they persist across screens.

Server processing (if enabled):
- When you request analysis or chat responses, the app sends the document text and your messages to our backend service to generate results.
- We do not sell your document text.
- We do not use your document text for advertising.

Retention:
- By default, we aim to minimize retention and store request data only as long as necessary to operate and secure the service (for example, to prevent abuse, troubleshoot errors, and maintain reliability).
- If you would like your data deleted from our systems, contact us using the email below and include the approximate time of your request.
NerdInventions@gmail.com
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("Sharing")
                                .font(.headline)

                            Text("""
- We do not sell your personal information.
- We do not share your document text with third parties except as needed to run the service (e.g., infrastructure providers that help deliver the backend).
- Purchases are handled by Apple. We receive entitlement status (e.g., Pro active) but do not receive your full payment details.
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("Your choices")
                                .font(.headline)

                            Text("""
- You can choose not to save documents/analyses. If you do save, they remain on your device until you delete them in the app or uninstall the app.
- You can delete saved items from the “Saved” section, and you can clear “Recents.”
- You can manage or cancel subscriptions in your Apple ID subscription settings.
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("Security")
                                .font(.headline)

                            Text("""
We use reasonable safeguards designed to protect data in transit and to reduce unnecessary access. However, no method of transmission or storage is 100% secure.
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            Text("Contact")
                                .font(.headline)

                            Text("""
If you have questions or privacy requests (including deletion requests), contact:
NerdInventions@gmail.com
""")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
    }
}
