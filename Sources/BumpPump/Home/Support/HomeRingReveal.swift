import SwiftUI

/// Radial expansion from the centre; the final chart always keeps its real values.
struct HomeRingReveal: ViewModifier {
  let token: String
  var identity = ""
  @Environment(\.accessibilityReduceMotion) private var reduced
  @State private var progress = 0.0
  func body(content: Content) -> some View {
    content
      .scaleEffect(reduced ? 1 : 0.15 + 0.85 * progress, anchor: .center)
      .opacity(progress)
      .blur(radius: reduced ? 0 : max(0, 3 * (1-progress)))
      .modifier(HomeRevealWhenVisible(progress: $progress, token: "ring|" + identity + "|" + token,
        animation: reduced ? .easeOut(duration: 0.12) : .appSpring(duration: 0.85, bounce: 0.12)))
  }
}
