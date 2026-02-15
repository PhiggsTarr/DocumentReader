//
//  SettingsView.swift
//  DocumentReader
//

import SwiftUI

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String?
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
                    .foregroundStyle(.tint) // ✅ blue icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "Purchasing…" : title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint) // ✅ blue title

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary) // ✅ keep subtitle gray
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .foregroundStyle(.tint) // ✅ blue spinner
                } else if let trailingText, !trailingText.isEmpty {
                    Text(trailingText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary) // ✅ keep price gray
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

    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(isProminent ? 0.0 : 0.10), lineWidth: 1)
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
}

struct SettingsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        ZStack {
            ScreenBackground()

            ScrollView {
                VStack(spacing: 14) {

                    Card("Pro / Subscription", icon: "star.fill", tint: .yellow) {
                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                Text("Status")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(purchaseManager.isPro ? "Pro Active" : "Free")
                                    .font(.headline)
                            }

                            HStack {
                                Text("Scans remaining")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(purchaseManager.isPro ? "Unlimited" : "\(purchaseManager.freeScansRemaining)")
                                    .font(.headline.monospacedDigit())
                            }

                            Divider().opacity(0.25)

                            // ✅ Pro (Monthly)
                            SettingsActionRow(
                                title: purchaseManager.isPro ? "Pro Active" : "Unlock Pro",
                                subtitle: purchaseManager.isPro ? "You already have unlimited scans" : "Best for frequent users",
                                leadingSystemImage: "crown.fill",
                                trailingText: purchaseManager.proProduct?.displayPrice,
                                isProminent: true,
                                isLoading: purchaseManager.isPurchasingPro,
                                isBlocked: purchaseManager.isPurchasingAny || purchaseManager.isPro
                            ) {
                                Task { await purchaseManager.purchasePro() }
                            }

                            // ✅ 10 scans (tap shows message if Pro is active)
                            SettingsActionRow(
                                title: "Buy 10 Scans",
                                subtitle: "Most Popular - Great Value",
                                leadingSystemImage: "cart.fill",
                                trailingText: purchaseManager.scanPack10Product?.displayPrice,
                                isProminent: false,
                                isLoading: purchaseManager.isPurchasingPack10,
                                isBlocked: purchaseManager.isPurchasingAny
                            ) {
                                if purchaseManager.isPro {
                                    purchaseManager.showAlreadyUnlimitedMessage()
                                } else {
                                    Task { await purchaseManager.purchaseScanPack10() }
                                }
                            }

                            // ✅ 5 scans (tap shows message if Pro is active)
                            SettingsActionRow(
                                title: "Buy 5 Scans",
                                subtitle: "Just Need A Few",
                                leadingSystemImage: "cart.fill",
                                trailingText: purchaseManager.scanPack5Product?.displayPrice,
                                isProminent: false,
                                isLoading: purchaseManager.isPurchasingPack5,
                                isBlocked: purchaseManager.isPurchasingAny
                            ) {
                                if purchaseManager.isPro {
                                    purchaseManager.showAlreadyUnlimitedMessage()
                                } else {
                                    Task { await purchaseManager.purchaseScanPack5() }
                                }
                            }

                            ThickDividerTwo()

                            SettingsActionRow(
                                title: "Restore Purchases",
                                subtitle: "Re-sync purchases on this device",
                                leadingSystemImage: "arrow.clockwise",
                                trailingText: nil,
                                isProminent: false,
                                isLoading: false,
                                isBlocked: purchaseManager.isPurchasingAny
                            ) {
                                Task { await purchaseManager.restorePurchases() }
                            }

                            SettingsActionRow(
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

                            if let err = purchaseManager.lastErrorMessage, !err.isEmpty {
                                Divider().opacity(0.25)
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    

                    Card("Legal", icon: "shield.lefthalf.filled", tint: .mint) {
                        VStack(spacing: 10) {
                            NavigationLink {
                                TermsAndConditionsView { }
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
            await purchaseManager.ensureProductsLoaded()
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
