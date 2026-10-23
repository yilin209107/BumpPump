import SwiftUI

@MainActor final class SetupMotion: ObservableObject {
  @Published var busy = false
  @Published var pageOpacity = 1.0
  @Published var iconOpacity = 1.0
  @Published var radius: CGFloat = 28
  @Published var rippleOpacity = 0.0
  @Published var rippleCenter = CGPoint.zero
  var buttonRect = CGRect.zero
  private var transitionTask: Task<Void, Never>?
  static func coverRadius(size: CGSize, center: CGPoint) -> CGFloat {
    [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
      .map { hypot($0.x-center.x, $0.y-center.y) }.max()! + 4
  }
  func advance(to next: SetupPage, state: SetupState, size: CGSize, reduced: Bool, origin: CGRect? = nil) {
    guard !busy, state.page != next else { return }
    busy = true; state.error = nil
    let source = origin ?? buttonRect
    rippleCenter = source.isEmpty ? CGPoint(x: size.width/2, y: size.height*0.73) : CGPoint(x: source.midX, y: source.midY)
    var initial = Transaction(animation: nil)
    initial.disablesAnimations = true
    withTransaction(initial) {
      radius = source.isEmpty ? 28 : source.width/2
      rippleOpacity = reduced ? 0 : 1
    }
    withAnimation(.easeOut(duration: 0.15)) { iconOpacity = 0 }
    let cover = Self.coverRadius(size: size, center: rippleCenter)
    transitionTask = Task {
      do {
        // Commit the button-sized circle before animating, so SwiftUI does not
        // coalesce its opaque starting state with the transparent destination.
        if !reduced { try await Task.sleep(for: .milliseconds(20)) }
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: reduced ? 0.15 : 0.34)) { pageOpacity = 0 }
        if !reduced {
          withAnimation(.timingCurve(0.65, 0.02, 0.24, 1, duration: 0.78)) {
            radius = cover
            rippleOpacity = 0
          }
        }
        try await Task.sleep(for: .milliseconds(reduced ? 160 : 780))
        guard !Task.isCancelled else { return }
        state.connectionPhase = .idle
        state.page = next
        withAnimation(.easeOut(duration: reduced ? 0.18 : 0.48)) {
          pageOpacity = 1; rippleOpacity = 0
        }
        try await Task.sleep(for: .milliseconds(reduced ? 190 : 500))
        iconOpacity = 1; busy = false
      } catch { pageOpacity = 1; rippleOpacity = 0; iconOpacity = 1; busy = false }
    }
  }
  func cancel() { transitionTask?.cancel(); transitionTask = nil }
}
struct ContinueBounds: PreferenceKey {
  static let defaultValue = CGRect.zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
