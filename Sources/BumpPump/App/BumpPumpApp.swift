import AppKit
import SwiftUI

final class OnboardingDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    if let output = HomeFluidWallChecks.output { Task { await HomeFluidWallChecks.run(output) } }
    else if let output = HomeRingChecks.output { Task { await HomeRingChecks.run(output) } }
    else if let output = HomeChecks.output { Task { await HomeChecks.run(output) } }
    else if let output = OnboardingChecks.output { Task { await OnboardingChecks.run(output) } }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct BumpPumpApp: App {
  @NSApplicationDelegateAdaptor(OnboardingDelegate.self) var delegate
  @StateObject private var state = SetupState()
  @StateObject private var motion = SetupMotion()
  @Environment(\.openSettings) private var openSettings
  @AppStorage("BumpPump.settingsTab") private var settingsTab = "ai"
  var body: some Scene {
    WindowGroup("泵碰 · BumpPump", id: "onboarding") {
      SetupRootView(state: state, motion: motion)
        .frame(minWidth: 760, minHeight: 640)
        .background(WindowChrome(dark: state.dark))
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1120, height: 800)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("检查新版本…") { settingsTab = "about"; openSettings() }
      }
      CommandGroup(replacing: .newItem) {
        Button("新增记录") { NotificationCenter.default.post(name: .newFitnessRecord, object: nil) }.keyboardShortcut("n").disabled(state.presentsOnboarding)
        Button("刷新记录") { NotificationCenter.default.post(name: .refreshFitnessRecords, object: nil) }.keyboardShortcut("r").disabled(state.presentsOnboarding)
        Button("查看使用教程") {
          guard !motion.busy && !state.saving else { return }
          state.reviewTutorial()
        }.keyboardShortcut("r", modifiers: [.command, .shift])
      }
    }
    Settings {
      AppSettingsView(setup: state)
    }
  }
}
/// Native window appearance follows the system; the content layout stays SwiftUI.
private struct WindowChrome: NSViewRepresentable {
  let dark: Bool
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else { return }
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.titlebarSeparatorStyle = .none
      window.isMovableByWindowBackground = false
      window.backgroundColor = NSColor(SetupPalette(dark: dark).background)
      window.appearance = nil
    }
  }
}

extension Notification.Name {
  static let newFitnessRecord = Notification.Name("BumpPump.newRecord")
  static let refreshFitnessRecords = Notification.Name("BumpPump.refreshRecords")
}
