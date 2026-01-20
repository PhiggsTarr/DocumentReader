//
//  RootView.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/19/26.
//


import SwiftUI

struct RootView: View {
    enum Phase {
        case splash
        case terms
        case app
    }

    @State private var phase: Phase = .splash

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation(.easeOut(duration: 0.6)) {
                                phase = TermsState.isAccepted ? .app : .terms
                            }
                        }
                    }

            case .terms:
                TermsAndConditionsView {
                    TermsState.accept()
                    withAnimation(.easeOut(duration: 0.6)) {
                        phase = .app
                    }
                }
                .transition(.opacity)

            case .app:
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}


import Foundation

enum TermsState {
    static let acceptedKey = "terms.accepted.v1"

    static var isAccepted: Bool {
        UserDefaults.standard.bool(forKey: acceptedKey)
    }

    static func accept() {
        UserDefaults.standard.set(true, forKey: acceptedKey)
    }
}
