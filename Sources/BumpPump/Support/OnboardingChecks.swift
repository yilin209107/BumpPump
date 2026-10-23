import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

@MainActor enum OnboardingChecks {
  static var output: String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: "--onboarding-check"), a.count > i+1 else { return nil }
    return a[i+1]
  }
  static func run(_ output: String) async {
    let dir = URL(fileURLWithPath: output)
    var report: [String: Any] = [:]
    let suite = "FitnessSetup.UIQA." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = SetupState(defaults: defaults), motion = SetupMotion()
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1120,height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "首次设置 · 应用内检查"
    defer { window.orderOut(nil); NSApp.terminate(nil) }
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      func require(_ condition: Bool, _ message: String) throws { if !condition { throw NSError(domain: "OnboardingCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
      try require(!state.validateAPI(), "Empty key should be rejected")
      for provider in APIProvider.all {
        state.selectProvider(provider)
        state.apiKey = "synthetic-preview-token"
        if provider.id == "custom" {
          state.model = "my-model"; state.endpoint = "http://invalid.example"
          try require(!state.validateAPI(), "Insecure custom endpoint should be rejected")
          state.endpoint = "https://example.invalid/v1"
        }
        try require(state.validateAPI(), "Provider configuration validation failed: " + provider.name)
      }
      state.selectProvider(APIProvider.all[0]); state.apiKey = ""; state.error = nil
      report["providerCount"] = APIProvider.all.count
      report["validation"] = "passed; no requests sent"
      for size in [CGSize(width: 760,height: 640),CGSize(width: 1120,height: 800),CGSize(width: 1600,height: 1000)] {
        for center in [CGPoint(x: 10,y: 10),CGPoint(x: size.width/2,y: size.height*0.7),CGPoint(x: size.width-30,y: size.height-30)] {
          let radius = SetupMotion.coverRadius(size: size, center: center)
          for corner in [CGPoint.zero,CGPoint(x: size.width,y: 0),CGPoint(x: 0,y: size.height),CGPoint(x: size.width,y: size.height)] {
            try require(radius > hypot(corner.x-center.x,corner.y-center.y), "Expansion does not cover the window")
          }
        }
      }
      report["cornerCoverage"] = "passed: 3 window sizes, 3 button origins, all corners"
      var captures: [String] = []
      for dark in [true,false] {
        for page in SetupPage.allCases {
          for narrow in [false,true] {
            state.dark = dark; state.page = page; state.error = nil
            let width: CGFloat = narrow ? 760 : 1120
            let height: CGFloat = narrow ? 640 : 800
            let root = SetupFlowView(state: state,motion: motion,preview: true,fixedTime: 8)
              .frame(width: width,height: height)
            let host = NSHostingView(rootView: root)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.setContentSize(NSSize(width: width,height: height)); window.contentView = host; window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(180))
            let name = "\(page.rawValue+1)-\(page.caption)-\(dark ? "dark" : "light")\(narrow ? "-compact" : "").png"
            try png(host, to: dir.appendingPathComponent(name)); captures.append(name)
          }
        }
      }
      report["captures"] = captures
      // Feedback visuals use fixtures only; never load or send a production credential.
      state.page = .api; state.dark = true
      let feedbackRoot = SetupFlowView(state: state, motion: motion, preview: true, fixedTime: 8)
        .frame(width: 1120, height: 800)
      let feedbackHost = NSHostingView(rootView: feedbackRoot)
      window.setContentSize(NSSize(width: 1120, height: 800)); window.appearance = NSAppearance(named: .darkAqua)
      window.contentView = feedbackHost; window.orderFront(nil)
      try await Task.sleep(for: .milliseconds(200))
      let baseline = window.frame.origin
      state.error = APIConnectionError.authentication.localizedDescription
      state.connectionPhase = .failure; state.shakeID += 1
      var moved = false
      for i in 0..<18 {
        try await Task.sleep(for: .milliseconds(30))
        if abs(window.frame.origin.x-baseline.x) > 0.5 { moved = true }
        if i == 17 { try png(feedbackHost, to: dir.appendingPathComponent("api-failure.png")) }
      }
      try require(moved || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "Failure did not shake its actual NSWindow")
      try require(abs(window.frame.origin.x-baseline.x) < 0.5, "Window did not return to its original position")
      report["failureFeedback"] = "actual NSWindow moved and returned to baseline; centered red cross rendered"
      state.connectionPhase = .idle
      try await Task.sleep(for: .milliseconds(300))
      try png(feedbackHost, to: dir.appendingPathComponent("api-error-inline.png"))
      state.error = nil; state.connectionPhase = .success; state.recordingMode = .ai
      try await Task.sleep(for: .milliseconds(550))
      try png(feedbackHost, to: dir.appendingPathComponent("api-success.png"))
      let successGIF = CGImageDestinationCreateWithURL(dir.appendingPathComponent("success-to-tutorial.gif") as CFURL, UTType.gif.identifier as CFString, 22, nil)!
      CGImageDestinationSetProperties(successGIF, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
      for i in 0..<22 {
        if i == 5 { motion.advance(to: .preferences, state: state, size: CGSize(width: 1120, height: 800), reduced: false, origin: CGRect(x: 516, y: 356, width: 88, height: 88)) }
        try await Task.sleep(for: .milliseconds(90))
        if let cg = bitmap(feedbackHost)?.cgImage { CGImageDestinationAddImage(successGIF, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.09]] as CFDictionary) }
      }
      try require(CGImageDestinationFinalize(successGIF), "Success animation export failed")
      try require(state.page == .preferences && !motion.busy, "Success did not reach tutorial")
      try require(motion.rippleCenter == CGPoint(x: 560, y: 400), "Success expansion used the form arrow instead of the centered check")
      report["successFeedback"] = "centered check → 88pt circle expansion from window center → tutorial"
      try png(feedbackHost, to: dir.appendingPathComponent("tutorial-ai.png"))
      state.recordingMode = .manual
      try await Task.sleep(for: .milliseconds(200))
      try png(feedbackHost, to: dir.appendingPathComponent("tutorial-manual.png"))
      for dark in [true, false] {
        let help = NSHostingView(rootView: APIHelpSheet(palette: SetupPalette(dark: dark)))
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = help; window.setContentSize(NSSize(width: 650, height: 620))
        try await Task.sleep(for: .milliseconds(200))
        try png(help, to: dir.appendingPathComponent(dark ? "help-dark.png" : "help-light.png"))
      }
      let adaptive = SetupState(defaults: defaults)
      let adaptiveHost = NSHostingView(rootView: SetupFlowView(state: adaptive, motion: SetupMotion()).frame(width: 1120, height: 800))
      window.contentView = adaptiveHost; window.setContentSize(NSSize(width: 1120, height: 800))
      window.appearance = NSAppearance(named: .aqua)
      try await Task.sleep(for: .milliseconds(250)); try require(!adaptive.dark, "Light appearance did not follow environment")
      window.appearance = NSAppearance(named: .darkAqua)
      try await Task.sleep(for: .milliseconds(250)); try require(adaptive.dark, "Dark appearance did not follow environment")
      report["appearance"] = "tracks native light/dark environment; no manual switch"
      state.page = .welcome; state.dark = true
      let root = SetupFlowView(state: state,motion: motion,preview: true)
        .frame(width: 1120,height: 800)
      let host = NSHostingView(rootView: root)
      window.setContentSize(NSSize(width: 1120,height: 800));window.contentView = host;window.orderFront(nil)
      try await Task.sleep(for: .milliseconds(180))
      let actualOrigin = motion.buttonRect
      try require(abs(actualOrigin.width - 56) < 0.5 && abs(actualOrigin.height - 56) < 0.5, "First-run arrow must preserve its original 56pt solid circle and measured origin")
      report["buttonOrigin"] = ["x": actualOrigin.midX, "y": actualOrigin.midY, "width": actualOrigin.width]
      let gifURL = dir.appendingPathComponent("welcome-to-api.gif")
      guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 18, nil) else { throw NSError(domain: "GIF", code: 1) }
      CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
      for i in 0..<18 {
        if i == 2 {
          motion.advance(to: .api,state: state,size: CGSize(width:1120,height:800),reduced: false)
          motion.advance(to: .preferences,state: state,size: CGSize(width:1120,height:800),reduced: false)
        }
        try await Task.sleep(for: .milliseconds(90))
        if let cg = bitmap(host)?.cgImage {
          CGImageDestinationAddImage(gif, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.09]] as CFDictionary)
        }
      }
      try require(CGImageDestinationFinalize(gif), "GIF export failed")
      try require(state.page == .api && !motion.busy, "Transition completion or repeated-click guard failed")
      try require(motion.rippleCenter == CGPoint(x: actualOrigin.midX, y: actualOrigin.midY), "Welcome expansion did not start at the original circular arrow")
      report["transition"] = "original solid 56pt arrow → measured circular origin → full-window cover → API; repeated click ignored"
      // Record the same live background at two times to prove it changes, not a static image.
      try png(host,to:dir.appendingPathComponent("aurora-a.png"))
      try await Task.sleep(for:.milliseconds(900))
      try png(host,to:dir.appendingPathComponent("aurora-b.png"))
      let a = try Data(contentsOf: dir.appendingPathComponent("aurora-a.png"))
      let b = try Data(contentsOf: dir.appendingPathComponent("aurora-b.png"))
      try require(a != b,"Aurora did not change over time")
      report["aurora"] = "two live renders differ after 900ms"
      motion.advance(to:.preferences,state:state,size:CGSize(width:1120,height:800),reduced:true)
      try await Task.sleep(for:.milliseconds(420))
      try require(state.page == .preferences && !motion.busy && motion.rippleOpacity == 0,"Reduced-motion transition failed")
      report["reducedMotion"] = "short crossfade completed without an expansion"
      // Exercise the actual launch root, using an isolated preference domain only.
      let firstLaunch = SetupState(defaults: defaults)
      try require(firstLaunch.presentsOnboarding, "Fresh install skipped onboarding")
      firstLaunch.useManualMode(); firstLaunch.finishTutorial()
      let relaunch = SetupState(defaults: defaults)
      try require(!relaunch.presentsOnboarding, "Relaunch showed onboarding again")
      for dark in [true, false] {
        relaunch.dark = dark
        let ready = NSHostingView(rootView: SetupRootView(state: relaunch, motion: SetupMotion(), preview: true)
          .frame(width: 1120, height: 800))
        window.contentView = ready; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try await Task.sleep(for: .milliseconds(200))
        try png(ready, to: dir.appendingPathComponent(dark ? "relaunch-dark.png" : "relaunch-light.png"))
      }
      let configurationState = SetupState(defaults: defaults, page: .api)
      let configuration = NSHostingView(rootView: SetupFlowView(state: configurationState, motion: SetupMotion(), preview: true, configurationOnly: true)
        .frame(width: 900, height: 760))
      window.contentView = configuration; window.setContentSize(NSSize(width: 900, height: 760))
      try await Task.sleep(for: .milliseconds(200))
      try png(configuration, to: dir.appendingPathComponent("api-settings.png"))
      report["launchRouting"] = "fresh install → onboarding; completed tutorial → relaunch ready state; standalone API settings starts at API without welcome/tutorial"
      report["ok"] = true
    } catch { report["ok"] = false; report["error"] = error.localizedDescription }
    if let data = try? JSONSerialization.data(withJSONObject: report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:dir.appendingPathComponent("report.json"),options:.atomic) }
  }
  private static func bitmap(_ host: NSView) -> NSBitmapImageRep? {
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds,to: rep);return rep
  }
  private static func png(_ host: NSView,to url: URL) throws {
    guard let rep = bitmap(host),let data = rep.representation(using:.png,properties:[:]) else { throw NSError(domain:"Render",code:1) }
    try data.write(to:url)
  }
}
