//
//  DesignSystem.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/11/26.
//

import SwiftUI

enum DS {
    static let pagePadding: CGFloat = 16
    static let corner: CGFloat = 20
}

struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
    }
}

struct ScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.9),
                Color.black.opacity(0.75),
                Color.black.opacity(0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

extension View {
    func polishedNavBar() -> some View {
        self
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
