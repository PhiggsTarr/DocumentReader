//
//  PurchaseManager.swift
//  DocumentReader
//

import Foundation
import StoreKit
import UIKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    // MARK: - Product IDs

    // Pro: subscription that enables unlimited scans
    let proProductId = "com.nerdinventions.smartfriendlegaltranslator.monthly_scans"

    // Scan packs: should be CONSUMABLE products in App Store Connect
    let scanPack5ProductId  = "com.NerdInventions.SmartFriendLegalTranslator.5IndividualScans"
    let scanPack10ProductId = "com.NerdInventions.SmartFriendLegalTranslator.IndividualScan"

    // MARK: - Published state

    @Published private(set) var isPro: Bool = false
    @Published private(set) var freeScansRemaining: Int = 0

    // Use this to display both errors + friendly info messages in UI
    @Published var lastErrorMessage: String? = nil

    // ✅ Track which product is being purchased (so only one button shows loading)
    @Published private(set) var purchasingProductId: String? = nil

    // Optional: to show prices
    @Published private(set) var proProduct: Product? = nil
    @Published private(set) var scanPack5Product: Product? = nil
    @Published private(set) var scanPack10Product: Product? = nil

    private let defaults = UserDefaults.standard
    private let scansKey = "scan.remaining.v3"

    private var transactionUpdatesTask: Task<Void, Never>? = nil

    private init() {
        // ✅ Only set the default if it doesn't exist
        if defaults.object(forKey: scansKey) == nil {
            defaults.set(2, forKey: scansKey)
        }
        freeScansRemaining = defaults.integer(forKey: scansKey)

        // Keep entitlements synced if Apple updates transactions while app is running
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self.handleVerifiedTransaction(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    // MARK: - UI helpers

    var isPurchasingAny: Bool { purchasingProductId != nil }

    func isPurchasing(productId: String) -> Bool {
        purchasingProductId == productId
    }

    var isPurchasingPro: Bool { purchasingProductId == proProductId }
    var isPurchasingPack5: Bool { purchasingProductId == scanPack5ProductId }
    var isPurchasingPack10: Bool { purchasingProductId == scanPack10ProductId }

    // MARK: - Scan gating

    func canScan() -> Bool {
        if isPro { return true }
        return freeScansRemaining > 0
    }

    func consumeFreeScanIfNeeded() {
        guard !isPro else { return }
        guard freeScansRemaining > 0 else { return }
        freeScansRemaining -= 1
        defaults.set(freeScansRemaining, forKey: scansKey)
    }

    func addScans(_ count: Int) {
        guard count > 0 else { return }
        freeScansRemaining += count
        defaults.set(freeScansRemaining, forKey: scansKey)
    }

    // MARK: - Friendly messages

    func showAlreadyUnlimitedMessage() {
        lastErrorMessage = "You already have Unlimited Scans with Pro. No need to buy scan packs."
    }

    private func shouldBlockScanPackPurchase() -> Bool {
        if isPro {
            showAlreadyUnlimitedMessage()
            return true
        }
        return false
    }

    // MARK: - Entitlements + product loading

    func refreshEntitlements() async {
        await loadProducts()

        var proActive = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == proProductId {
                // Extra safety: revoked subscriptions shouldn't count
                if transaction.revocationDate == nil {
                    proActive = true
                }
            }
        }

        isPro = proActive
    }

    private func loadProducts() async {
        do {
            let ids = [proProductId, scanPack5ProductId, scanPack10ProductId]
            let products = try await Product.products(for: ids)

            self.proProduct = products.first(where: { $0.id == proProductId })
            self.scanPack5Product = products.first(where: { $0.id == scanPack5ProductId })
            self.scanPack10Product = products.first(where: { $0.id == scanPack10ProductId })
        } catch {
            print("⚠️ Failed to load products:", error.localizedDescription)
        }
    }

    // MARK: - Purchases

    func purchasePro() async {
        await purchase(productId: proProductId, grantScans: nil)
    }

    func purchaseScanPack5() async {
        if shouldBlockScanPackPurchase() { return }
        await purchase(productId: scanPack5ProductId, grantScans: 5)
    }

    func purchaseScanPack10() async {
        if shouldBlockScanPackPurchase() { return }
        await purchase(productId: scanPack10ProductId, grantScans: 10)
    }

    private func purchase(productId: String, grantScans: Int?) async {
        // ✅ Prevent overlapping purchases without disabling UI
        guard purchasingProductId == nil else { return }

        lastErrorMessage = nil
        purchasingProductId = productId
        defer { purchasingProductId = nil }

        do {
            let products = try await Product.products(for: [productId])
            guard let product = products.first else {
                lastErrorMessage = "Unable to load purchase option."
                return
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    if let n = grantScans {
                        addScans(n)
                    }

                    await transaction.finish()
                    await refreshEntitlements()

                case .unverified:
                    lastErrorMessage = "Purchase could not be verified."
                }

            case .userCancelled:
                break

            case .pending:
                lastErrorMessage = "Purchase is pending approval."

            @unknown default:
                lastErrorMessage = "Unknown purchase state."
            }

        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if transaction.productID == proProductId {
            await refreshEntitlements()
            return
        }

        if transaction.productID == scanPack5ProductId {
            addScans(5)
            return
        }

        if transaction.productID == scanPack10ProductId {
            addScans(10)
            return
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Manage subscriptions

    func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }
}
