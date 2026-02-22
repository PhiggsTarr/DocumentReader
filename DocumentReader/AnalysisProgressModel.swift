//
//  AnalysisProgressModel.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 1/11/26.
//

import SwiftUI
import Lottie

// MARK: - Model

@MainActor
final class AnalysisProgressModel: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var progress: Double = 0.0 // 0...1
    @Published var statusText: String = "Analyzing"

    /// Lottie file name (NO .json)
    let lottieName: String = "BookFlipper"

    private let statuses = ["Analyzing", "Interpreting", "Researching", "Summarizing", "Drafting"]
    private var statusIndex: Int = 0

    private var progressTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    private var progressCap: Double = 0.15
    private var creepTask: Task<Void, Never>?

    // ✅ Fix: lock the status once progress crosses 95%
    private var isFinishingUpLocked: Bool = false
    private let finishingUpThreshold: Double = 0.89

    func start() {
        stop()

        progress = 0.02
        statusIndex = 0
        statusText = statuses[statusIndex]
        isPresented = true
        isFinishingUpLocked = false

        progressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isPresented {
                try? await Task.sleep(nanoseconds: 120_000_000)

                if self.progress < 0.98 {
                    self.progress = min(self.progress + 0.006, self.progressCap)
                }

                // ✅ When we cross 95%, lock status text to finishing message
                if !self.isFinishingUpLocked, self.progress >= self.finishingUpThreshold {
                    self.isFinishingUpLocked = true
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.statusText = """
Preparing your results
Please be patient 
"""
                    }
                }
            }
        }

        statusTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isPresented {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // ✅ Gate rotating statuses once we’re in “finishing up” state
                if self.isFinishingUpLocked { continue }

                self.statusIndex = (self.statusIndex + 1) % self.statuses.count
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.statusText = self.statuses[self.statusIndex]
                }
            }
        }
    }

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
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.stop()
        }
    }

    func stop() {
        progressTask?.cancel()
        statusTask?.cancel()
        creepTask?.cancel()
        progressTask = nil
        statusTask = nil
        creepTask = nil
        isPresented = false

        // ✅ reset
        isFinishingUpLocked = false
    }

    func startCreep(to targetCap: Double, tickNs: UInt64 = 350_000_000) {
        creepTask?.cancel()

        let target = min(max(targetCap, 0.0), 1.0)

        creepTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isPresented {
                try? await Task.sleep(nanoseconds: tickNs)

                // If we've already reached the cap, stop creeping.
                if self.progressCap >= target { break }

                // Ease as we approach target (slows down near the end)
                let remaining = target - self.progressCap
                let step = max(0.003, remaining * 0.08)

                let nextCap = min(target, self.progressCap + step)

                await MainActor.run {
                    // Drive cap forward; progressTask will animate progress up to that cap.
                    self.moveTo(cap: nextCap)
                }
            }
        }
    }

    func stopCreep() {
        creepTask?.cancel()
        creepTask = nil
    }
}

// MARK: - Overlay UI

struct AnalysisProgressOverlay: View {
    @ObservedObject var model: AnalysisProgressModel
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                LottieStage(
                    animationName: model.lottieName,
                    speed: 2.2,                         // faster flips
                    stageSize: CGSize(width: 260, height: 150),
                    zoom: 1.35,                          // tweak this (1.0 - 2.0)
                    yOffset: -6                          // tweak this (-30 ... 30)
                )
                .accessibilityHidden(true)
                
                Text(model.statusText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)

                Text("Working on your document…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("May take a few minutes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Divider().opacity(0.25)

                Button(role: .cancel) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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

// MARK: - Lottie Stage (frames + “camera”)

struct LottieStage: View {
    let animationName: String
    var speed: CGFloat
    var stageSize: CGSize
    var zoom: CGFloat
    var yOffset: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )

            LottieLoopingView(
                animationName: animationName,
                speed: speed,
                zoom: zoom,
                yOffset: yOffset
            )
            .padding(10)
        }
        .frame(width: stageSize.width, height: stageSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Lottie UIViewRepresentable

struct LottieLoopingView: UIViewRepresentable {
    let animationName: String
    var speed: CGFloat
    var zoom: CGFloat
    var yOffset: CGFloat

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isOpaque = false

        // Force rendering engine (some animations only render correctly on mainThread)
        let config = LottieConfiguration(renderingEngine: .mainThread)

        let animationView = LottieAnimationView(configuration: config)
        animationView.backgroundColor = .clear
        animationView.isOpaque = false

        if let animation = LottieAnimation.named(animationName) {
            animationView.animation = animation
        } else {
            print("❌ Lottie animation not found in bundle: \(animationName).json")
        }

        animationView.loopMode = .loop
        animationView.animationSpeed = speed

        // We will “camera” with transform, so keep aspectFit.
        animationView.contentMode = .scaleAspectFit

        // Let container handle clipping
        animationView.clipsToBounds = false
        animationView.backgroundBehavior = .pauseAndRestore

        container.addSubview(animationView)
        animationView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        animationView.play()

        // Save reference
        context.coordinator.animationView = animationView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let animationView = context.coordinator.animationView else { return }

        animationView.animationSpeed = speed

        // Camera transform: zoom + vertical offset to frame the book
        let clampedZoom = max(0.5, min(zoom, 3.0))
        let t = CGAffineTransform(translationX: 0, y: yOffset)
            .scaledBy(x: clampedZoom, y: clampedZoom)
        animationView.transform = t

        if animationView.isAnimationPlaying == false {
            animationView.play()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var animationView: LottieAnimationView?
    }
}
