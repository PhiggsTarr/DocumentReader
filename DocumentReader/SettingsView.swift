//
//  SettingsView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/18/26.
//


//
//  SettingsView.swift
//  DocumentReader
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {

                    // MARK: - Pro / Subscription
                    Card("Pro / Subscription", icon: "star.fill", tint: .yellow) {
                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                Text("Status")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(purchaseManager.isPro ? "Pro Active" : "Free")
                                    .font(.headline)
                            }

                            if !purchaseManager.isPro {
                                HStack {
                                    Text("Free scans remaining")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(purchaseManager.freeScansRemaining)")
                                        .font(.headline.monospacedDigit())
                                }
                            }

                            Divider().opacity(0.25)

                            Button {
                                Task { await purchaseManager.purchasePro() }
                            } label: {
                                HStack {
                                    Image(systemName: "cart.fill")
                                    Text(purchaseManager.isPurchasing ? "Purchasing…" : "Unlock Pro")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(purchaseManager.isPurchasing || purchaseManager.isPro)

                            Button {
                                Task { await purchaseManager.restorePurchases() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Restore Purchases")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                purchaseManager.openManageSubscriptions()
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                    Text("Manage Subscription")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)

                            if let err = purchaseManager.lastErrorMessage, !err.isEmpty {
                                Divider().opacity(0.25)
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // MARK: - Legal
                    Card("Legal", icon: "shield.lefthalf.filled", tint: .mint) {
                        VStack(spacing: 10) {
                            NavigationLink {
                                TermsAndConditionsView {
                                    // This screen is usually only shown as the gate.
                                    // But letting users re-read is good for App Review.
                                }
                            } label: {
                                row("Terms & Conditions", icon: "doc.text")
                            }

                            Divider().opacity(0.25)

                            NavigationLink {
                                PrivacyPolicyView()
                            } label: {
                                row("Privacy Policy", icon: "hand.raised.fill")
                            }
                        }
                    }

//                    #if DEBUG
//                    Card("Developer", icon: "hammer.fill", tint: .purple) {
//                        VStack(spacing: 10) {
//                            Button {
//                                purchaseManager.debugResetFreeScans()
//                            } label: {
//                                HStack {
//                                    Image(systemName: "arrow.counterclockwise")
//                                    Text("Reset free scans (Debug)")
//                                        .fontWeight(.semibold)
//                                    Spacer()
//                                }
//                                .padding(.vertical, 6)
//                            }
//                            .buttonStyle(.bordered)
//                        }
//                    }
//                    #endif

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
        .task {
            await purchaseManager.refreshEntitlements()
        }
    }

    private func row(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
    }
}
