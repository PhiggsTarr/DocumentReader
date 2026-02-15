//
//  TermsGateModifier.swift
//  DocumentReader
//

import SwiftUI

private enum TermsStorage {
    static let acceptedKey = "terms.accepted.v1"
}

/// Gate that forces the Terms screen to be accepted once per install (or until user defaults cleared).
struct TermsGateModifier: ViewModifier {

    // ✅ Persisted state
    @AppStorage(TermsStorage.acceptedKey) private var accepted: Bool = false

    // ✅ Real presentation state (SwiftUI can dismiss normally)
    @State private var showTerms: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Present only if not accepted
                showTerms = !accepted
            }
            .onChange(of: accepted) { _, newValue in
                // If accepted flips true, dismiss the cover
                if newValue { showTerms = false }
            }
            .fullScreenCover(isPresented: $showTerms) {
                TermsAndConditionsView(onAccept: {
                    // ✅ Set acceptance FIRST so the cover won’t re-appear during dismissal
                    accepted = true
                    showTerms = false
                })
            }
    }
}

extension View {
    func termsGate() -> some View {
        modifier(TermsGateModifier())
    }
}
