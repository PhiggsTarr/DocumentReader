//
//  DesignSystem.swift
//  DocumentReader
//
//  Shared design system + common UI helpers
//

import SwiftUI

enum DS {
    static let pagePadding: CGFloat = 16
    static let corner: CGFloat = 22
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
}

// MARK: - Card

struct Card<Content: View>: View {
    let title: String?
    let icon: String?
    let tint: Color?
    let content: Content

    init(_ title: String? = nil,
         icon: String? = nil,
         tint: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionHeader(title: title, icon: icon, tint: tint)
            }
            content
        }
        .padding(DS.cardPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DS.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.corner, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String?
    let tint: Color?

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))   // slightly bigger icon
                    .foregroundStyle((tint ?? .white).opacity(0.95))
                    .frame(width: 30, height: 30)
                    .background((tint ?? .white).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text(title)
                .font(.title2)              // ⬅️ bigger than .headline
                .fontWeight(.heavy)         // ⬅️ bolder
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.bottom, 4)                // gives breathing room
    }
}


// MARK: - Pill

struct Pill: View {
    let text: String
    let icon: String?
    let tone: Tone

    enum Tone {
        case neutral, good, warning, bad

        var background: Color {
            switch self {
            case .neutral: return .white.opacity(0.10)
            case .good: return .green.opacity(0.18)
            case .warning: return .orange.opacity(0.18)
            case .bad: return .red.opacity(0.18)
            }
        }

        var foreground: Color {
            switch self {
            case .neutral: return .white.opacity(0.92)
            case .good: return .green.opacity(0.95)
            case .warning: return .orange.opacity(0.95)
            case .bad: return .red.opacity(0.95)
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(text)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tone.background)
        .clipShape(Capsule())
    }
}

// MARK: - Background

struct ScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color.black.opacity(0.85),
                Color.black.opacity(0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Nav styling

extension View {
    /// Keep ONLY ONE definition of this in your project to avoid "ambiguous use" errors.
    func polishedNavBar() -> some View {
        self
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
