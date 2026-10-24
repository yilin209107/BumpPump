import SwiftUI

/// Owned by one page identity, rather than HomeState or a process singleton.
/// Non-publishing writes keep hover and other view updates from restarting work.
final class HomePageAnimationLedger: ObservableObject {
  private var started = Set<String>()
  func contains(_ token: String) -> Bool { started.contains(token) }
  func insert(_ token: String) { started.insert(token) }
  func remove(_ token: String) { started.remove(token) }
}
private struct HomePageAnimationLedgerKey: EnvironmentKey { static let defaultValue: HomePageAnimationLedger? = nil }
private struct HomeViewportKey: EnvironmentKey { static let defaultValue: CGRect? = nil }
extension EnvironmentValues {
  var homePageAnimationLedger: HomePageAnimationLedger? {
    get { self[HomePageAnimationLedgerKey.self] }
    set { self[HomePageAnimationLedgerKey.self] = newValue }
  }
  var homeScrollViewport: CGRect? {
    get { self[HomeViewportKey.self] }
    set { self[HomeViewportKey.self] = newValue }
  }
}

/// Placed on the ScrollView, outside its scrolling content. Nested horizontal
/// scrollers intersect the vertical viewport, so an offscreen row cannot start.
struct HomeScrollViewport: ViewModifier {
  @Environment(\.homeScrollViewport) private var parent
  @State private var viewport: CGRect?
  func body(content: Content) -> some View {
    content.environment(\.homeScrollViewport, effectiveViewport)
      .onGeometryChange(for: CGRect.self) { proxy in proxy.frame(in: .global) } action: { frame in
        if viewport != frame { viewport = frame }
      }
  }
  private var effectiveViewport: CGRect {
    guard let viewport else { return .zero } // No reveal before the first real layout.
    return parent.map { viewport.intersection($0) } ?? viewport
  }
}

/// A small entrance threshold and zero-area exit provide hysteresis: grazing
/// the threshold does not repeatedly fade a card in and out while scrolling.
private enum HomeVisibilityBand: Equatable, Sendable { case outside, edge, inside }
private struct HomeVisibleInScroll: ViewModifier {
  @Environment(\.homeScrollViewport) private var viewport
  let changed: (Bool) -> Void
  @State private var nativeVisible = false
  @State private var band = HomeVisibilityBand.outside
  @State private var reportedVisible = false
  @ViewBuilder func body(content: Content) -> some View {
    if #available(macOS 15.0, *), viewport != nil {
      content
        .onScrollVisibilityChange(threshold: 0.001) { value in
          nativeVisible = value
          report(native: true)
        }
        .onGeometryChange(for: HomeVisibilityBand.self) { proxy in visibilityBand(proxy.frame(in: .global)) } action: { value in
          band = value
          report(native: true)
        }
    } else {
      content.onGeometryChange(for: HomeVisibilityBand.self) { proxy in visibilityBand(proxy.frame(in: .global)) } action: { value in
        band = value
        report(native: false)
      }
    }
  }
  private func report(native: Bool) {
    let next: Bool
    switch band {
    case .outside: next = false
    case .edge: next = reportedVisible
    case .inside: next = !native || nativeVisible || reportedVisible
    }
    guard next != reportedVisible else { return }
    reportedVisible = next
    changed(next)
  }
  private func visibilityBand(_ frame: CGRect) -> HomeVisibilityBand {
    guard frame.width > 0, frame.height > 0 else { return .outside }
    guard let viewport else { return .inside } // Standalone previews and native check windows.
    let intersection = frame.intersection(viewport)
    guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return .outside }
    // Cap the reference at the viewport, so tall sections and wide history
    // charts can enter without requiring most of their entire area onscreen.
    let reference = min(frame.width * frame.height, viewport.width * viewport.height)
    return reference > 0 && intersection.width * intersection.height / reference >= 0.08 ? .inside : .edge
  }
}

private struct HomeRevealRequest: Equatable {
  let key: String
  let visible: Bool
  let windowVisible: Bool
}

/// First visible entrance only for this data token within one page lifetime.
/// Lazy recycling and window restoration retain the final state; navigation
/// creates a new page ledger. No timer runs while waiting outside the viewport.
struct HomeRevealWhenVisible: ViewModifier {
  @Binding var progress: Double
  let token: String
  let animation: Animation
  var delay: Duration = .milliseconds(25)
  var replayOnTokenChange = false
  @Environment(\.appAnimationsVisible) private var windowVisible
  @Environment(\.homePageAnimationLedger) private var ledger
  @State private var visible = false
  @State private var localStarted = Set<String>()
  @State private var previousToken: String?
  func body(content: Content) -> some View {
    content.modifier(HomeVisibleInScroll { visible = $0 })
      .task(id: HomeRevealRequest(key: token, visible: visible, windowVisible: windowVisible)) {
        if replayOnTokenChange, let previousToken, previousToken != token {
          localStarted.remove(token); ledger?.remove(token)
        }
        previousToken = token
        if hasStarted { setImmediately(1); return }
        setImmediately(0)
        guard visible, windowVisible else { return }
        do { try await Task.sleep(for: max(delay, .milliseconds(80))) } catch { return }
        guard !Task.isCancelled else { return }
        localStarted.insert(token)
        ledger?.insert(token)
        withAnimation(animation) { progress = 1 }
      }
      .onDisappear { setImmediately(hasStarted ? 1 : 0) }
  }
  private var hasStarted: Bool { localStarted.contains(token) || ledger?.contains(token) == true }
  private func setImmediately(_ value: Double) {
    guard progress != value else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { progress = value }
  }
}
