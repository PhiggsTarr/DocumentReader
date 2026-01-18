//
//  TermsGateModifier.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/18/26.
//


import SwiftUI

private enum TermsStorage {
    static let acceptedKey = "terms.accepted.v1"
}

struct TermsGateModifier: ViewModifier {
    @State private var accepted: Bool = UserDefaults.standard.bool(forKey: TermsStorage.acceptedKey)

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: .constant(!accepted)) {
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

