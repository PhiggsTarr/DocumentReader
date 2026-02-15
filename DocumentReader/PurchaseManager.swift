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

    // Scan packs (CONSUMABLE)
    let scanPack5ProductId  = "com.NerdInventions.SmartFriendLegalTranslator.5IndividualScans"
    let scanPack10ProductId = "com.NerdInventions.SmartFriendLegalTranslator.IndividualScan"
    
    private var didInitialEntitlementsRefresh = false


    // MARK: - UI/Product loading state

    enum ProductsState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var productsState: ProductsState = .idle

    /// Use this to display error messages in UI
    @Published var lastErrorMessage: String? = nil

    /// Optional: non-error, user-facing status (e.g. cancelled)
    @Published var lastInfoMessage: String? = nil

    // ✅ Track which product is being purchased (so only one button shows loading)
    @Published private(set) var purchasingProductId: String? = nil

    // MARK: - Published entitlements

    @Published private(set) var isPro: Bool = false
    @Published private(set) var freeScansRemaining: Int = 0

    // MARK: - Products (for prices)

    @Published private(set) var proProduct: Product? = nil
    @Published private(set) var scanPack5Product: Product? = nil
    @Published private(set) var scanPack10Product: Product? = nil

    // MARK: - Persistence

    private let defaults = UserDefaults.standard
    private let scansKey = "scan.remaining.v3"

    // ✅ Prevent double-granting consumables across purchase() + Transaction.updates
    private let processedTxKey = "processed.tx.ids.v1"

    // MARK: - Transaction updates task

    private var transactionUpdatesTask: Task<Void, Never>? = nil

    private init() {
        // ✅ Only set the default if it doesn't exist
        if defaults.object(forKey: scansKey) == nil {
            defaults.set(1, forKey: scansKey)
        }
        freeScansRemaining = defaults.integer(forKey: scansKey)

        // Keep entitlements synced if Apple updates transactions while app is running
        transactionUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self.processVerifiedTransaction(transaction)
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }

        // Proactively load products so buttons show prices quickly
        Task {
            await refreshEntitlements()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }
    
    func refreshEntitlementsIfNeeded() async {
        guard !didInitialEntitlementsRefresh else { return }
        didInitialEntitlementsRefresh = true
        await refreshEntitlements()
    }


    // MARK: - UI helpers

    var isPurchasingAny: Bool { purchasingProductId != nil }

    func isPurchasing(productId: String) -> Bool {
        purchasingProductId == productId
    }

    var isPurchasingPro: Bool { purchasingProductId == proProductId }
    var isPurchasingPack5: Bool { purchasingProductId == scanPack5ProductId }
    var isPurchasingPack10: Bool { purchasingProductId == scanPack10ProductId }

    var canAttemptPurchases: Bool {
        switch productsState {
        case .loaded:
            return true
        default:
            return false
        }
    }

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

    // MARK: - Public: retry product loading (for “Couldn’t load purchases. Retry.”)

    func retryLoadPurchases() async {
        await loadProducts(force: true)
    }

    // MARK: - Entitlements + product loading

    func refreshEntitlements() async {
        await loadProducts(force: false)

        // ✅ compute off the main actor to avoid UI hangs during transitions
        let proActive = await PurchaseManager.fetchProActiveEntitlement(proProductId: proProductId)

        // Back on MainActor (we're already @MainActor), safe to assign published state
        isPro = proActive
    }

    /// Runs off-main (static + no @MainActor isolation), avoids blocking UI
    private static func fetchProActiveEntitlement(proProductId: String) async -> Bool {
        var proActive = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == proProductId, transaction.revocationDate == nil {
                proActive = true
                break
            }
        }
        return proActive
    }


    func ensureProductsLoaded() async -> Bool {
        switch productsState {
        case .loaded:
            return true
        case .loading:
            // Wait briefly and let the UI keep showing loading.
            // (No blocking loop; just attempt a reload if needed.)
            return (proProduct != nil) || (scanPack5Product != nil) || (scanPack10Product != nil)
        case .failed:
            return false
        case .idle:
            await loadProducts(force: false)
            return productsState == .loaded
        }
    }

    private func loadProducts(force: Bool) async {
        if !force, case .loaded = productsState { return }
        if case .loading = productsState { return }

        productsState = .loading
        lastErrorMessage = nil
        lastInfoMessage = nil

        do {
            let ids = [proProductId, scanPack5ProductId, scanPack10ProductId]
            let products = try await Product.products(for: ids)

            self.proProduct = products.first(where: { $0.id == proProductId })
            self.scanPack5Product = products.first(where: { $0.id == scanPack5ProductId })
            self.scanPack10Product = products.first(where: { $0.id == scanPack10ProductId })

            // If Apple returns 0 products (bad IDs / account / StoreKit issue), treat as failure so UI shows Retry.
            if proProduct == nil && scanPack5Product == nil && scanPack10Product == nil {
                productsState = .failed("Couldn’t load purchases. Retry.")
            } else {
                productsState = .loaded
            }
        } catch {
            let message = friendlyStoreKitMessage(from: error)
            productsState = .failed(message.isEmpty ? "Couldn’t load purchases. Retry." : message)
        }
    }

    // MARK: - Purchases

    func purchasePro() async {
        await purchase(productId: proProductId)
    }

    func purchaseScanPack5() async {
        if shouldBlockScanPackPurchase() { return }
        await purchase(productId: scanPack5ProductId)
    }

    func purchaseScanPack10() async {
        if shouldBlockScanPackPurchase() { return }
        await purchase(productId: scanPack10ProductId)
    }

    private func purchase(productId: String) async {
        // ✅ Prevent overlapping purchases (prevents double-taps)
        guard purchasingProductId == nil else { return }

        lastErrorMessage = nil
        lastInfoMessage = nil

        // ✅ If products aren’t loaded, don’t allow “tap did nothing”
        let ready = await ensureProductsLoaded()
        guard ready else {
            lastErrorMessage = "Couldn’t load purchases. Retry."
            return
        }

        purchasingProductId = productId
        defer { purchasingProductId = nil } // ✅ guarantees spinner stops (cancel/error/success)

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
                    // ✅ Single source of truth: never grant here directly.
                    // processVerifiedTransaction handles Pro + consumables, idempotently.
                    await processVerifiedTransaction(transaction)
                    await transaction.finish()
                    await refreshEntitlements()

                case .unverified:
                    lastErrorMessage = "Purchase could not be verified."
                }

            case .userCancelled:
                lastInfoMessage = "Purchase cancelled."

            case .pending:
                lastErrorMessage = "Purchase is pending approval."

            @unknown default:
                lastErrorMessage = "Unknown purchase state."
            }
        } catch {
            // ✅ Airplane mode / no internet / StoreKit auth issues become friendly + recoverable
            lastErrorMessage = friendlyStoreKitMessage(from: error)
        }
    }

    // MARK: - Transaction processing (idempotent)

    private func loadProcessedTxIDs() -> Set<UInt64> {
        let arr = defaults.array(forKey: processedTxKey) as? [NSNumber] ?? []
        return Set(arr.map { $0.uint64Value })
    }

    private func saveProcessedTxIDs(_ set: Set<UInt64>) {
        defaults.set(set.map { NSNumber(value: $0) }, forKey: processedTxKey)
    }

    /// Returns true if this transaction was not processed before (i.e., safe to grant)
    private func markTransactionProcessed(_ id: UInt64) -> Bool {
        var set = loadProcessedTxIDs()
        if set.contains(id) { return false }
        set.insert(id)
        saveProcessedTxIDs(set)
        return true
    }

    /// Centralized transaction handler used by BOTH purchase() and Transaction.updates
    private func processVerifiedTransaction(_ transaction: Transaction) async {
        // Subscription: just refresh entitlements
        if transaction.productID == proProductId {
            await refreshEntitlements()
            return
        }

        // Consumables: grant exactly once per transaction.id
        guard markTransactionProcessed(transaction.id) else {
            // Already granted; do nothing
            return
        }

        if transaction.productID == scanPack5ProductId {
            addScans(5)
        } else if transaction.productID == scanPack10ProductId {
            addScans(10)
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        lastErrorMessage = nil
        lastInfoMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastInfoMessage = "Purchases restored."
        } catch {
            lastErrorMessage = friendlyStoreKitMessage(from: error)
        }
    }

    // MARK: - Manage subscriptions

    func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Error mapping

    private func friendlyStoreKitMessage(from error: Error) -> String {
        // Common network failures (Airplane Mode, no service, etc.)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "No internet connection. Please check your network (Wi-Fi/Cellular) and try again."
            default:
                break
            }
        }

        let nsError = error as NSError

        // StoreKit / App Store authentication issues
        if nsError.domain == SKErrorDomain {
            // Some auth failures show up as 509
            if nsError.code == 509 {
                return "No App Store account found. Please sign into the App Store (Settings → App Store) and try again."
            }

            if nsError.code == SKError.Code.cloudServicePermissionDenied.rawValue {
                return "No internet connection. Please check your network (Wi-Fi/Cellular) and try again."
            }

            switch nsError.code {
            case SKError.paymentNotAllowed.rawValue:
                return "In-App Purchases are disabled on this device."
            case SKError.storeProductNotAvailable.rawValue:
                return "This purchase is not available in your region."
            default:
                break
            }
        }

        // Fallback
        return error.localizedDescription
    }
}
