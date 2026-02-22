import SwiftUI
import AudioToolbox

struct SplashView: View {
    private let fullText = "SmartFriend"
    @State private var displayedText = ""
    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Image("SmartFriend Legal Translator App Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 288, height: 288)

                Text(displayedText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospaced()

                Text("Legal Translator AI")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .opacity(displayedText == fullText ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: displayedText)
            }
        }
        .onAppear { typeText() }
    }

    private func typeText() {
        guard index < fullText.count else { return }
        let chars = Array(fullText)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            displayedText.append(chars[index])
            playSound()
            index += 1
            typeText()
        }
    }

    private func playSound() {
        AudioServicesPlaySystemSound(1104)
        // Optional: add a subtle haptic too
        // UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
