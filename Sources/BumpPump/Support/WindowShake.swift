import AppKit
import SwiftUI

/// Only this window moves; the coordinator owns and cancels its short animation.
struct WindowShake: NSViewRepresentable {
  let trigger: Int
  let reducedMotion: Bool
  func makeNSView(context: Context) -> NSView { NSView() }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func updateNSView(_ view: NSView, context: Context) {
    guard context.coordinator.lastTrigger != trigger else { return }
    context.coordinator.lastTrigger = trigger
    guard trigger > 0, !reducedMotion else { return }
    context.coordinator.shake(view: view)
  }
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.cancel() }
  @MainActor final class Coordinator {
    var lastTrigger = 0
    var task: Task<Void, Never>?
    weak var window: NSWindow?
    var origin: CGPoint?
    func cancel() {
      task?.cancel(); task = nil
      if let origin { window?.setFrameOrigin(origin) }
      origin = nil
    }
    func shake(view: NSView) {
      cancel()
      task = Task { [weak self, weak view] in
        await Task.yield()
        guard let self, let window = view?.window, !window.styleMask.contains(.fullScreen) else { return }
        self.window = window; let start = window.frame.origin; self.origin = start
        do {
          for offset: CGFloat in [-10, 9, -7, 5, -3, 1, 0] {
            try Task.checkCancellation()
            window.setFrameOrigin(CGPoint(x: start.x+offset, y: start.y))
            try await Task.sleep(for: .milliseconds(45))
          }
          self.origin = nil
        } catch { window.setFrameOrigin(start); self.origin = nil }
      }
    }
  }
}
