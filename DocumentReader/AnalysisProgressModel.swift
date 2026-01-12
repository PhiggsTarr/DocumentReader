//
//  AnalysisProgressModel.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/11/26.
//


import SwiftUI

@MainActor
final class AnalysisProgressModel: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var progress: Double = 0.0 // 0...1
    @Published var statusText: String = "Analyzing"

    private let statuses = ["Analyzing", "Interpreting", "Researching", "Summarizing", "Drafting"]
    private var statusIndex: Int = 0

    private var progressTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    func start() {
        stop()

        progress = 0.02
        statusIndex = 0
        statusText = statuses[statusIndex]
        isPresented = true

        // Smooth fake progress
        progressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isPresented {
                try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s
                // Slowly creep upward, but don't exceed current "cap"
                // Cap will be controlled by moveTo(...)
                if self.progress < 0.98 {
                    self.progress = min(self.progress + 0.006, self.progressCap)
                }
            }
        }

        // Rotate words every 2 seconds
        statusTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isPresented {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                self.statusIndex = (self.statusIndex + 1) % self.statuses.count
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.statusText = self.statuses[self.statusIndex]
                }
            }
        }
    }

    /// Where the fake progress is allowed to climb to right now (0...1).
    private var progressCap: Double = 0.15

    /// Call this at milestones (after OCR, after request started, etc.)
    func moveTo(cap newCap: Double) {
        withAnimation(.easeInOut(duration: 0.25)) {
            progressCap = min(max(newCap, 0.0), 1.0)
            if progress > progressCap { progress = progressCap }
        }
    }

    func finishAndDismiss() {
        progressCap = 1.0
        withAnimation(.easeOut(duration: 0.25)) {
            progress = 1.0
            statusText = "Done"
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000) // 0.45s
            self?.stop()
        }
    }

    func stop() {
        progressTask?.cancel()
        statusTask?.cancel()
        progressTask = nil
        statusTask = nil
        isPresented = false
    }
}

import SwiftUI

struct AnalysisProgressOverlay: View {
    @ObservedObject var model: AnalysisProgressModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                BookFlipAnimation()
                    .frame(width: 160, height: 120)

                Text(model.statusText)
                    .font(.headline)

                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)

                Text("Working on your document…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(radius: 30)
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: model.isPresented)
    }
}


// MARK: - Book flip + hand animation (pure SwiftUI, no assets)

/// Animated "researching" book: pages riffle quickly while two hands alternate flipping.


/// Reliable "researching" animation using TimelineView (always animates).
/// One hand flips pages quickly like searching.
struct BookFlipAnimation: View {

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            // 0...1 repeating cycle
            let cycle = (t * 1.15).truncatingRemainder(dividingBy: 1.0)

            // page flip progress with a tiny pause at start
            let p = remapWithPause(cycle, pause: 0.08)

            ZStack {
                bookBase
                turningPage(progress: p)
                flippingHand(progress: p)
            }
            .frame(width: 160, height: 120)
            .accessibilityLabel("Researching")
        }
    }

    // MARK: - Book

    private var bookBase: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08))
                )

            // spine + faint pages
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.primary.opacity(0.10))
                    .frame(width: 7)

                Rectangle()
                    .fill(.primary.opacity(0.03))

                Rectangle()
                    .fill(.primary.opacity(0.03))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(10)

            // text blocks
            VStack(spacing: 6) {
                HStack(spacing: 12) { linesBlock; linesBlock }
                HStack(spacing: 12) { linesBlock; linesBlock }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .opacity(0.7)
        }
    }

    private var linesBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(.primary.opacity(0.10)).frame(width: 90, height: 6)
            Capsule().fill(.primary.opacity(0.08)).frame(width: 74, height: 6)
            Capsule().fill(.primary.opacity(0.07)).frame(width: 84, height: 6)
        }
    }

    // MARK: - Page

    private func turningPage(progress: Double) -> some View {
        // smoothstep
        let p = progress * progress * (3 - 2 * progress)

        // rotate like a page turning from right to left
        let angle = -p * 120.0
        let xOffset = -p * 24.0

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.62))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06))
            )
            .frame(width: 150, height: 78)
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 6)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .offset(x: xOffset, y: 2)
            .opacity(progress < 0.02 ? 0 : 1)
            .allowsHitTesting(false)
            .zIndex(2)
    }

    // MARK: - Hand (one hand, moving)

    private func flippingHand(progress: Double) -> some View {
        // Stage motion
        let reach = clamp((progress - 0.00) / 0.25)
        let drag  = clamp((progress - 0.25) / 0.55)
        let back  = clamp((progress - 0.80) / 0.20)

        // coming in from right, then dragging page left, then retract
        let x = 56.0 - (reach * 18.0) - (drag * 58.0) + (back * 22.0)
        let y = 20.0 - (reach * 10.0) - (drag * 6.0)  + (back * 8.0)

        let rot = (-8.0 * reach) + (-26.0 * drag) + (10.0 * back)
        let scale = 1.0 + (reach * 0.05) + (drag * 0.03)

        return Image(systemName: "hand.raised.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
            .scaleEffect(x: -1, y: 1) // face left
            .scaleEffect(scale)
            .rotationEffect(.degrees(rot))
            .offset(x: x, y: y)
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 4)
            .allowsHitTesting(false)
            .zIndex(3)
    }

    // MARK: - Helpers

    private func clamp(_ x: Double) -> Double {
        min(max(x, 0), 1)
    }

    private func remapWithPause(_ t: Double, pause: Double) -> Double {
        // t: 0..1
        if t < pause { return 0 }
        return (t - pause) / (1 - pause)
    }
}
