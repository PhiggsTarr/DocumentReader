//
//  Entitlements.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/18/26.
//

import Foundation
import SwiftUI

/// Persists lightweight gates (1 free scan + terms accepted + premium unlock).
enum Entitlements {
    // One-time "1 free scan" gate
    @AppStorage("freeScanUsed") static var freeScanUsed: Bool = false

    // Premium unlock (non-consumable or active subscription)
    @AppStorage("hasPremium") static var hasPremium: Bool = false

    // Terms gate
    @AppStorage("acceptedTerms") static var acceptedTerms: Bool = false

    /// Call before starting a scan.
    /// - Returns: true if scan should proceed, false if you must show paywall.
    static func canStartScanAndConsumeFreeIfNeeded() -> Bool {
        if hasPremium { return true }

        if !freeScanUsed {
            freeScanUsed = true
            return true
        }

        return false
    }
}
