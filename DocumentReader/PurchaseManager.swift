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

    // ✅ Use your real product id
    private let proProductId = "com.NerdInventions.SmartFriendLegalTranslator.IndividualScan"

    @Published private(set) var isPro: Bool = false
    @Published private(set) var freeScansRemaining: Int = 1
    @Published var lastErrorMessage: String? = nil
    @Published var isPurchasing: Bool = false

    private let defaults = UserDefaults.standard
    private let freeKey = "scan.free.remaining.v1"

    
    private init() {
        if defaults.object(forKey: freeKey) == nil {
            defaults.set(2, forKey: freeKey)
        }
        freeScansRemaining = defaults.integer(forKey: freeKey)
    }

    func refreshEntitlements() async {
        var proActive = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == proProductId {
                    proActive = true
                    break
                }
            }
        }
        isPro = proActive
    }

    func canScan() -> Bool {
        if isPro {
            return true }
        return freeScansRemaining > 0
    }

    func consumeFreeScanIfNeeded() {
        guard !isPro else { return }
        guard freeScansRemaining > 0 else { return }
        freeScansRemaining -= 1
        defaults.set(freeScansRemaining, forKey: freeKey)
    }

    func purchasePro() async {
        lastErrorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let products = try await Product.products(for: [proProductId])
            guard let product = products.first else {
                lastErrorMessage = "Unable to load purchase option."
                return
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    freeScansRemaining += 10
                    if defaults.object(forKey: freeKey) == nil {
                        defaults.set(10, forKey: freeKey)
                    } else {
                        defaults.set(defaults.object(forKey: freeKey) as! Int + 10, forKey: freeKey)
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

    func restorePurchases() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Manage subscriptions (Apple UI)

    func openManageSubscriptions() {
        // Apple’s official subscriptions management page (opens App Store / Settings)
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Debug tooling

//    #if DEBUG
//    func debugResetFreeScans() {
//        freeScansRemaining = 1
//        defaults.set(1, forKey: freeKey)
//        UINotificationFeedbackGenerator().notificationOccurred(.success)
//    }
//    #endif
}
