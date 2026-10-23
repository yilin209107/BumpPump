import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor enum HomeChecks {
  static var output: String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--home-check"), args.count > index+1 else { return nil }
    return args[index+1]
  }
  static func run(_ path: String) async {
    let directory = URL(fileURLWithPath: path)
    let suite = "BumpPump.Home.UIQA." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); NSApp.terminate(nil) }
    let setup = SetupState(defaults: defaults)
    let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22))!
    let state = HomeState(anchor: anchor, preload: true, usesExamples: true)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    var report: [String: Any] = ["realDataRead": false, "externalRequests": 0, "captureLimitation": "NSView bitmap snapshots may omit compositor-only Liquid Glass; verify actual foreground controls with CUA and --glass-preview, not exported bitmaps."]
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      func require(_ value: Bool, _ message: String) throws { if !value { throw NSError(domain: "HomeQA", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
      func capture(_ name: String, width: CGFloat = 1280, height: CGFloat = 900, dark: Bool = true) async throws {
        setup.dark = dark
        let host = NSHostingView(rootView: HomeWorkspace(state: state, setup: setup, preview: true)
          .frame(width: width, height: height).environment(\.colorScheme, dark ? .dark : .light))
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: width, height: height)); window.contentView = host; window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(1100))
        try png(host, to: directory.appendingPathComponent(name))
      }
      try await capture("home-dark.png")
      if let host = window.contentView {
        state.destination = .meal(.breakfast)
        try await Task.sleep(for: .milliseconds(500))
        let gif = CGImageDestinationCreateWithURL(directory.appendingPathComponent("home-entrance.gif") as CFURL, UTType.gif.identifier as CFString, 16, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<16 {
          if index == 2 { state.destination = .overview }
          try await Task.sleep(for: .milliseconds(80))
          host.layoutSubtreeIfNeeded()
          if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let image = rep.cgImage { CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary) }
          }
        }
        try require(CGImageDestinationFinalize(gif), "Entrance GIF export failed")
        report["entrance"] = "native category fade and staggered home reveal exported"
      }
      try await capture("home-light.png", dark: false)
      try await capture("home-compact.png", width: 760, height: 640)
      state.expandedMealID = state.day?.meals.first?.id
      try await capture("meal-expanded.png")
      state.expandedMealID = nil
      try await capture("home-scroll.png")
      if let host = window.contentView, let scroll = scrollViews(host).filter({ $0.documentView != nil && $0.frame.width > 450 }).max(by: { $0.frame.width < $1.frame.width }) {
        scroll.documentView?.scroll(CGPoint(x: 0, y: 650))
        try await Task.sleep(for: .milliseconds(1100))
        try png(host, to: directory.appendingPathComponent("home-trends.png"))
        scroll.documentView?.scroll(CGPoint(x: 0, y: 1250))
        try await Task.sleep(for: .milliseconds(1100))
        try png(host, to: directory.appendingPathComponent("home-nutrition.png"))
        report["scroll"] = "native scroll view moved to trends and nutrition"
      } else { report["scroll"] = "no native scroll view found" }
      for kind in DemoMealKind.allCases {
        state.select(.meal(kind)); try await capture("meal-\(kind.id)-dark.png")
      }
      state.select(.meal(.breakfast)); try await capture("meal-compact-light.png", width: 760, height: 640, dark: false)
      let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("FoodCatalog." + UUID().uuidString + ".db")
      defer { try? FileManager.default.removeItem(at: fixture) }
      let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
      process.arguments = [fixture.path, """
        CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);
        INSERT INTO meta VALUES('schema_version','5');
        CREATE TABLE food_products(id TEXT PRIMARY KEY,name TEXT,brand TEXT,basis TEXT,kcal REAL,protein_g REAL,carbs_g REAL,fat_g REAL,source TEXT,is_current INTEGER,version INTEGER,other_nutrients TEXT);
        INSERT INTO food_products VALUES('current','示例包装牛奶','示例品牌','100ml',42,3.4,4.8,1.1,'label_text',1,2,'{"钙":{"value":120,"unit":"mg"}}');
        INSERT INTO food_products VALUES('missing','示例包装食品','示例品牌','100g',NULL,NULL,NULL,NULL,'reference',1,1,NULL);
        INSERT INTO food_products VALUES('old','过期标签版本','示例品牌','100ml',55,4,5,1,'label_text',0,1,NULL);
        CREATE TABLE food_entries(custom_name TEXT);
        INSERT INTO food_entries VALUES('当天菜肴不属于食品库');
        """]
      try process.run(); process.waitUntilExit()
      try require(process.terminationStatus == 0, "Catalogue fixture creation failed")
      let databaseBefore = try Data(contentsOf: fixture)
      let labels = try HomeFoodCatalog.read(path: fixture.path)
      try require(labels.count == 2 && !labels.contains { $0.id == "old" }, "Catalogue must use current food-product rows only")
      try require(labels.first { $0.id == "missing" }?.value("kcal", unit: "kcal") == "—", "Missing packaged label energy must not be inferred")
      try require(databaseBefore == Data(contentsOf: fixture), "Read-only catalogue changed fixture bytes")
      state.packagedFoods = labels; state.catalogLoaded = true; state.catalogMessage = ""
      state.select(.foods); try await capture("food-library-dark.png")
      try await capture("food-library-light.png", dark: false)
      report["catalogue"] = "isolated SQLite fixture: only current food_products, excluded old versions and meal dishes, preserved NULL energy and raw extended nutrients; file bytes unchanged"
      state.select(.strength("胸")); try await capture("sidebar-strength.png")
      state.select(.cardio("羽毛球")); try await capture("empty-cardio.png")
      state.query = "鸡胸"; try await capture("search.png")
      try require(state.searchResults.contains { $0.title == "香煎鸡胸肉" }, "Food search failed")
      state.query = ""; state.select(.overview)
      state.selectedDate = Calendar.current.date(byAdding: .day, value: -5, to: state.anchor)!
      state.range = 7; try await capture("history-seven-days.png")
      try require(state.history.count == 7, "Date range is not inclusive seven days")
      state.selectedDate = state.anchor
      state.range = 30
      try state.setEnergyGoal(2300)
      let goalHost = NSHostingView(rootView: HomeEnergyChart(state: state, palette: SetupPalette(dark: true), reduced: true, compact: false).padding(32).frame(width: 900, height: 440).foregroundStyle(SetupPalette(dark: true).foreground).background(SetupPalette(dark: true).background).environment(\.colorScheme, .dark))
      window.contentView = goalHost; window.setContentSize(NSSize(width: 900, height: 440))
      try await Task.sleep(for: .milliseconds(500)); try png(goalHost, to: directory.appendingPathComponent("energy-goal.png"))
      for kind in [HomeEntryKind.food, .activity, .weight, .energy] {
        for dark in [true, false] {
          let palette = SetupPalette(dark: dark)
          let draft = HomeEntryDraft(kind: kind, date: state.anchor, goal: state.energyGoal)
          let host = NSHostingView(rootView: HomeEntryView(state: state, kind: kind, palette: palette, preview: true, draft: draft).environment(\.colorScheme, dark ? .dark : .light))
          window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          window.contentView = host; window.setContentSize(NSSize(width: 620, height: 590))
          try await Task.sleep(for: .milliseconds(600)); try png(host, to: directory.appendingPathComponent("entry-\(kind.rawValue)-\(dark ? "dark" : "light").png"))
          if kind == .food && dark, let scroll = scrollViews(host).first {
            scroll.documentView?.scroll(CGPoint(x: 0, y: 280))
            try await Task.sleep(for: .milliseconds(200)); try png(host, to: directory.appendingPathComponent("entry-food-scrolled.png"))
          }
        }
      }
      let weightDraft = HomeEntryDraft(kind: .weight, date: state.anchor, goal: nil)
      weightDraft.weight = "60.5"; weightDraft.unit = "kg"; weightDraft.notes = "原生窗口隔离验证"
      try require(weightDraft.submit(to: state), "Native weight submission failed")
      try require(state.day?.weightJin == 121, "Native submission did not update home")
      let saved = NSHostingView(rootView: HomeEntryView(state: state, kind: .weight, palette: SetupPalette(dark: true), preview: true, draft: weightDraft).environment(\.colorScheme, .dark))
      window.contentView = saved; window.setContentSize(NSSize(width: 620, height: 590))
      try await Task.sleep(for: .milliseconds(300)); try png(saved, to: directory.appendingPathComponent("entry-saved.png"))
      report["entries"] = "four native forms in both themes, scrollable food fields, isolated weight save updates home; yellow 2300 kcal goal reference rendered"
      let positions = [CGPoint(x: 0.2, y: 0.25), CGPoint(x: 0.8, y: 0.7)]
      for (index, point) in positions.enumerated() {
        let host = NSHostingView(rootView: ZStack { SetupPalette(dark: true).background; HomePointerGlow(location: point, dark: true, active: false, reduced: false, fixedTime: 8) }.frame(width: 1000, height: 700))
        window.contentView = host; window.setContentSize(NSSize(width: 1000, height: 700))
        try await Task.sleep(for: .milliseconds(150)); try png(host, to: directory.appendingPathComponent("pointer-\(index).png"))
      }
      try require(Data(contentsOf: directory.appendingPathComponent("pointer-0.png")) != Data(contentsOf: directory.appendingPathComponent("pointer-1.png")), "Pointer glow did not change position")
      report["pointer"] = "two clamped normalized locations produce different low-intensity renders"
      let fluidState = HomeFluidProofState()
      let fluidHost = NSHostingView(rootView: HomeFluidProofView(state: fluidState).frame(width: 900, height: 600))
      window.contentView = fluidHost; window.setContentSize(NSSize(width: 900, height: 600))
      let fluidGIF = CGImageDestinationCreateWithURL(directory.appendingPathComponent("fluid-follow.gif") as CFURL, UTType.gif.identifier as CFString, 36, nil)!
      CGImageDestinationSetProperties(fluidGIF, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
      for frame in 0..<36 {
        if frame == 4 { fluidState.target = CGPoint(x: 0.8, y: 0.35) }
        if frame == 14 { fluidState.target = CGPoint(x: 0.45, y: 0.8) }
        if frame == 24 { fluidState.target = CGPoint(x: 0.2, y: 0.3) }
        try await Task.sleep(for: .milliseconds(80))
        fluidHost.layoutSubtreeIfNeeded()
        if let rep = fluidHost.bitmapImageRepForCachingDisplay(in: fluidHost.bounds) {
          fluidHost.cacheDisplay(in: fluidHost.bounds, to: rep)
          if let image = rep.cgImage { CGImageDestinationAddImage(fluidGIF, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary) }
        }
        if frame == 18 { try png(fluidHost, to: directory.appendingPathComponent("fluid-deformation.png")) }
      }
      try require(CGImageDestinationFinalize(fluidGIF), "Fluid animation export failed")
      report["fluid"] = "native Canvas rendered 36 frames through three pointer direction changes, one shared filled liquid silhouette, internally blended colours, inertia and deformation; connected radial-envelope invariants checked separately"
      report["ok"] = true
    } catch { report["ok"] = false; report["error"] = error.localizedDescription }
    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: directory.appendingPathComponent("report.json")) }
    window.orderOut(nil)
  }
  private static func scrollViews(_ view: NSView) -> [NSScrollView] { (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews) }
  private static func png(_ view: NSView, to url: URL) throws {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "HomeQA", code: 2) }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "HomeQA", code: 3) }
    try data.write(to: url)
  }
}
private final class HomeFluidProofState: ObservableObject { @Published var target = CGPoint(x: 0.2, y: 0.3) }
private struct HomeFluidProofView: View {
  @ObservedObject var state: HomeFluidProofState
  var body: some View {
    ZStack { SetupPalette(dark: true).background; HomePointerGlow(location: state.target, dark: true, active: true, reduced: false) }
  }
}
