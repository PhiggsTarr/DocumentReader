//
//  ScanGate.swift
//  DocumentReader
//

import Foundation

enum ScanGate {
    @MainActor static func canStartScan(purchaseManager: PurchaseManager) -> Bool {
        return purchaseManager.canScan()
    }
}
