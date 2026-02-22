//
//  ScanCreditManager.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/23/26.
//

import Foundation

@MainActor
final class ScanCreditManager: ObservableObject {

    // If you already have a StoreKit manager / entitlement flag, inject it here.
    // For now, keep it as a settable bool.
    @Published var isPro: Bool = false

    // One free scan. After that, paywall unless Pro.
    @Published private(set) var freeScanUsed: Bool {
        didSet { UserDefaults.standard.set(freeScanUsed, forKey: Keys.freeScanUsed) }
    }

    // In-flight scan (so we can cancel without consuming)
    @Published private(set) var hasInFlightScan: Bool = false

    private enum Keys {
        static let freeScanUsed = "scan_credit_free_used_v1"
    }

    init() {
        self.freeScanUsed = UserDefaults.standard.bool(forKey: Keys.freeScanUsed)
    }

    var canStartScan: Bool {
        isPro || !freeScanUsed
    }

    /// Call when the user starts an analysis attempt (right before OCR/API work begins).
    func beginScanAttempt() {
        hasInFlightScan = true
    }

    /// Call ONLY when the analysis finishes successfully.
    func completeScanAttemptSuccessfully() {
        defer { hasInFlightScan = false }
        guard !isPro else { return }
        // Consume the single free scan only on success
        freeScanUsed = true
    }

    /// Call when user cancels or the attempt fails before completion.
    func cancelOrFailScanAttempt() {
        hasInFlightScan = false
        // IMPORTANT: no consumption here.
    }

    #if DEBUG
    func resetFreeScan() {
        freeScanUsed = false
        hasInFlightScan = false
    }
    #endif
}
