import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor enum HomeRingChecks {
  static var output: String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--ring-check"), args.count > i+1 else { return nil }
    return args[i+1]
  }
  static func run(_ path: String) async {
    let directory = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let size: CGFloat = 240
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: size, height: size), styleMask: [.titled], backing: .buffered, defer: false)
      let palette = SetupPalette(dark: true)
      let root = HomeMealRing(nutrition: .init(protein: 20, carbs: 35, fat: 8), palette: palette).frame(width: 200, height: 200).padding(20).background(palette.background).environment(\.colorScheme, .dark)
      let host = NSHostingView(rootView: root)
      window.contentView = host; window.makeKeyAndOrderFront(nil)
      let gif = CGImageDestinationCreateWithURL(directory.appendingPathComponent("ring-centre-expansion.gif") as CFURL, UTType.gif.identifier as CFString, 28, nil)!
      CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
      var widths: [Int] = [], centres: [Double] = []
      for _ in 0..<28 {
        try await Task.sleep(for: .milliseconds(40))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let frame = rep.cgImage {
          CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04]] as CFDictionary)
          var left = rep.pixelsWide, right = 0
          for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
              guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
              let maxC = max(c.redComponent, max(c.greenComponent, c.blueComponent)), minC = min(c.redComponent, min(c.greenComponent, c.blueComponent))
              if maxC-minC > 0.15 && maxC > 0.2 { left = min(left, x); right = max(right, x) }
            }
          }
          if right > left { widths.append(right-left); centres.append(Double(left+right)/Double(2*rep.pixelsWide)) }
        }
      }
      let exported = CGImageDestinationFinalize(gif)
      let expands = Double(widths.max() ?? 0) > Double(widths.min() ?? 0) * 1.25
      let centred = centres.allSatisfy { abs($0-0.5) < 0.06 }
      // Recompute the exact nutrition payload on pointer-like selection updates.
      // This catches unstable task identities that replay the radial entrance.
      let probe = RingStabilityModel()
      let stabilityHost = NSHostingView(rootView: RingStabilityProbe(model: probe, palette: palette).frame(width: 240, height: 240))
      window.contentView = stabilityHost
      try await Task.sleep(for: .milliseconds(1100))
      func coloredWidth() -> Int {
        stabilityHost.layoutSubtreeIfNeeded()
        guard let rep = stabilityHost.bitmapImageRepForCachingDisplay(in: stabilityHost.bounds) else { return 0 }
        stabilityHost.cacheDisplay(in: stabilityHost.bounds, to: rep)
        var left = rep.pixelsWide, right = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
          guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
          if max(c.redComponent,max(c.greenComponent,c.blueComponent))-min(c.redComponent,min(c.greenComponent,c.blueComponent)) > 0.15 { left = min(left,x); right = max(right,x) }
        } }
        return max(0,right-left)
      }
      var hoverWidths = [coloredWidth()]
      for i in 1...18 { probe.selection = i; try await Task.sleep(for: .milliseconds(55)); hoverWidths.append(coloredWidth()) }
      let stable = (hoverWidths.min() ?? 0) > 0 && (hoverWidths.max() ?? 0)-(hoverWidths.min() ?? 0) <= 4
      let report: [String: Any] = ["ok": exported && expands && centred && stable, "hoverDoesNotReplay": stable, "hoverWidths": hoverWidths, "radialWidths": widths, "centres": centres, "expandsFromCentre": expands, "noLeftToRightWipe": centred, "personalDataRead": false]
      try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("report.json"))
    } catch { try? String(describing: error).write(to: directory.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8) }
    NSApp.terminate(nil)
  }
}

@MainActor private final class RingStabilityModel: ObservableObject { @Published var selection = 0 }
private struct RingStabilityProbe: View {
  @ObservedObject var model: RingStabilityModel
  let palette: SetupPalette
  var body: some View {
    let missing = Set(model.selection.isMultiple(of: 2) ? ["kcal","protein_g","carbs_g"] : ["carbs_g","protein_g","kcal"])
    let nutrition = DemoNutrition(protein: 20, carbs: 35, fat: 8) + DemoNutrition(missing: missing)
    HomeMealRing(nutrition: nutrition, palette: palette).frame(width: 200, height: 200).padding(20).background(palette.background)
      .accessibilityLabel("Selection \(model.selection)")
  }
}
