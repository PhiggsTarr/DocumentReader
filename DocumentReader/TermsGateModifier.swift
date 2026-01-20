//
//  TermsGateModifier.swift
//  DocumentReader
//

import SwiftUI

private enum TermsStorage {
    static let acceptedKey = "terms.accepted.v1"
}

struct TermsGateModifier: ViewModifier {
    @State private var accepted: Bool = UserDefaults.standard.bool(forKey: TermsStorage.acceptedKey)

    private var shouldShowGate: Bool { !accepted }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(
                get: { shouldShowGate },
                set: { _ in } // no-op; acceptance drives dismissal
            )) {
                TermsAndConditionsView {
                    accepted = true
                    UserDefaults.standard.set(true, forKey: TermsStorage.acceptedKey)
                }
            }
    }
}

extension View {
    func termsGate() -> some View {
        modifier(TermsGateModifier())
    }
}
