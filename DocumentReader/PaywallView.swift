//
//  PaywallView.swift
//  DocumentReader
//

import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    Card("Upgrade", icon: "lock.open.fill", tint: .mint) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You’ve used your free scan.")
                                .font(.headline)

                            Text("Unlock unlimited scans and continue analyzing documents anytime.")
                                .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            HStack {
                                Text("Free scans remaining")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(purchaseManager.freeScansRemaining)")
                                    .font(.headline.monospacedDigit())
                            }

                            if purchaseManager.isPro {
                                Text("✅ Pro is active on this device.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Card("Get Pro", icon: "star.fill", tint: .yellow) {
                        VStack(spacing: 10) {
                            Button {
                                Task { await purchaseManager.purchasePro() }
                            } label: {
                                HStack {
                                    Image(systemName: "cart.fill")
                                    Text(purchaseManager.isPurchasing ? "Purchasing…" : "Unlock Unlimited Scans")
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
                        }
                    }

                    if let err = purchaseManager.lastErrorMessage, !err.isEmpty {
                        Card("Purchase Error", icon: "exclamationmark.triangle.fill", tint: .red) {
                            Text(err)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ✅ Terms/Privacy footer (App Store review expectation)
                    Card(nil) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("By continuing, you agree to our Terms and Privacy Policy.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                NavigationLink("Terms") {
                                    TermsAndConditionsView { }
                                }
                                .font(.footnote.weight(.semibold))

                                NavigationLink("Privacy Policy") {
                                    PrivacyPolicyView()
                                }
                                .font(.footnote.weight(.semibold))

                                Spacer()
                            }
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Not now")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Upgrade")
        .navigationBarTitleDisplayMode(.inline)
        .polishedNavBar()
        .task {
            await purchaseManager.refreshEntitlements()
        }
    }
}
