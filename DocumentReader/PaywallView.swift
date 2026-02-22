//
//  PaywallView.swift
//  DocumentReader
//

import SwiftUI
import StoreKit

private struct PaywallPurchaseRow: View {
    let title: String
    let subtitle: String
    let leadingSystemImage: String
    let trailingText: String?
    let isProminent: Bool

    let isLoading: Bool
    let isBlocked: Bool
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: leadingSystemImage)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "Loading…" : title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .foregroundStyle(.tint)
                } else if let trailingText {
                    Text(trailingText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(border)
            .opacity(isBlocked && !isLoading ? 0.95 : 1.0)
            .opacity(isPressed ? 0.90 : 1.0)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isBlocked)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in
                    state = true
                }
        )
    }

    private var background: some View {
        Group {
            if isProminent {
                Color.white.opacity(0.14)
            } else {
                Color.white.opacity(0.06)
            }
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(isProminent ? 0.0 : 0.10), lineWidth: 1)
    }
}

struct PaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    private var isProductsLoading: Bool {
        if case .loading = purchaseManager.productsState { return true }
        if case .idle = purchaseManager.productsState { return true } // treat idle like loading for UI
        return false
    }

    private var productsFailedMessage: String? {
        if case .failed(let msg) = purchaseManager.productsState { return msg }
        return nil
    }

    private var purchasesReady: Bool {
        purchaseManager.canAttemptPurchases
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    Card("Upgrade", icon: "lock.open.fill", tint: .mint) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You’ve used your free scans.")
                                .font(.headline)

                            Text("Choose Pro for unlimited scans or buy scan packs when you need them.")
                                .foregroundStyle(.secondary)

                            Divider().opacity(0.25)

                            HStack {
                                Text("Scans remaining")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(purchaseManager.isPro ? "Unlimited (Pro)" : "\(purchaseManager.freeScansRemaining)")
                                    .font(.headline.monospacedDigit())
                            }

                            if purchaseManager.isPro {
                                Text("✅ Pro is active on this device.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // ✅ Product loading / failure state surfaced clearly (prevents “tap did nothing”)
                    if let msg = productsFailedMessage {
                        Card("Purchases", icon: "exclamationmark.triangle.fill", tint: .yellow) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(msg.isEmpty ? "Couldn’t load purchases. Retry." : msg)
                                    .foregroundStyle(.secondary)

                                Button {
                                    Task { await purchaseManager.retryLoadPurchases() }
                                } label: {
                                    Text("Retry")
                                        .font(.footnote.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    } else if isProductsLoading {
                        Card("Purchases", icon: "arrow.triangle.2.circlepath", tint: .mint) {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading purchase options…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Card("Scan Packs", icon: "plus.circle.fill", tint: .mint) {
                        VStack(spacing: 10) {

                            // Pro / Unlimited
                            PaywallPurchaseRow(
                                title: purchaseManager.isPro ? "Pro Active" : "Unlimited Monthly Scans",
                                subtitle: purchaseManager.isPro
                                    ? "You already have unlimited scans"
                                    : "Best for frequent users",
                                leadingSystemImage: "crown.fill",
                                trailingText: purchasesReady ? purchaseManager.proProduct?.displayPrice : "Loading…",
                                isProminent: true,
                                // ✅ show spinner while purchasing OR while products are loading
                                isLoading: purchaseManager.isPurchasingPro || isProductsLoading,
                                // ✅ block tapping until products are loaded + while another purchase is running + if Pro already active
                                isBlocked: purchaseManager.isPurchasingAny || !purchasesReady || purchaseManager.isPro
                            ) {
                                Task { await purchaseManager.purchasePro() }
                            }

                            // 10 scans
                            PaywallPurchaseRow(
                                title: "Buy 10 scans",
                                subtitle: "Most popular • Great value",
                                leadingSystemImage: "plus.circle.fill",
                                trailingText: purchasesReady ? purchaseManager.scanPack10Product?.displayPrice : "Loading…",
                                isProminent: false,
                                isLoading: purchaseManager.isPurchasingPack10 || isProductsLoading,
                                isBlocked: purchaseManager.isPurchasingAny || !purchasesReady
                            ) {
                                if purchaseManager.isPro {
                                    purchaseManager.showAlreadyUnlimitedMessage()
                                } else {
                                    Task { await purchaseManager.purchaseScanPack10() }
                                }
                            }

                            // 5 scans
                            PaywallPurchaseRow(
                                title: "Buy 5 scans",
                                subtitle: "Just need a few",
                                leadingSystemImage: "plus.circle.fill",
                                trailingText: purchasesReady ? purchaseManager.scanPack5Product?.displayPrice : "Loading…",
                                isProminent: false,
                                isLoading: purchaseManager.isPurchasingPack5 || isProductsLoading,
                                isBlocked: purchaseManager.isPurchasingAny || !purchasesReady
                            ) {
                                if purchaseManager.isPro {
                                    purchaseManager.showAlreadyUnlimitedMessage()
                                } else {
                                    Task { await purchaseManager.purchaseScanPack5() }
                                }
                            }

                            ThickDividerTwo()

                            PaywallPurchaseRow(
                                title: "Restore Purchases",
                                subtitle: "Re-sync purchases on this device",
                                leadingSystemImage: "arrow.clockwise",
                                trailingText: nil,
                                isProminent: false,
                                isLoading: false,
                                isBlocked: purchaseManager.isPurchasingAny || !purchasesReady
                            ) {
                                Task { await purchaseManager.restorePurchases() }
                            }

                            PaywallPurchaseRow(
                                title: "Manage Subscription",
                                subtitle: "Open Apple Subscriptions",
                                leadingSystemImage: "person.crop.circle.badge.checkmark",
                                trailingText: nil,
                                isProminent: false,
                                isLoading: false,
                                isBlocked: purchaseManager.isPurchasingAny
                            ) {
                                purchaseManager.openManageSubscriptions()
                            }
                        }
                    }

                    // ✅ Show friendly info (e.g. “Purchase cancelled.”) separately from errors
                    if let info = purchaseManager.lastInfoMessage, !info.isEmpty {
                        Card("Status", icon: "info.circle.fill", tint: .mint) {
                            Text(info)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let err = purchaseManager.lastErrorMessage, !err.isEmpty {
                        Card("Purchase", icon: "info.circle.fill", tint: .mint) {
                            Text(err)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Card(nil) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("By continuing, you agree to our Terms and Privacy Policy.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                NavigationLink("Terms") {
                                    // This view is informational in Paywall. Your “gate” should be handled by TermsGateModifier.
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
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .buttonStyle(.plain)
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
            await Task.yield()
            await purchaseManager.refreshEntitlementsIfNeeded()
        }
    }
}
