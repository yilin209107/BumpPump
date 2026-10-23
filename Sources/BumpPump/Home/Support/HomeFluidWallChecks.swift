import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// A synthetic native render, without records, credentials, or external requests.
@MainActor enum HomeFluidWallChecks {
  static var output: String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--wall-check"), args.count > i+1 else { return nil }
    return args[i+1]
  }
  static func run(_ path: String) async {
    let directory = URL(fileURLWithPath: path)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let model = WallProofModel()
      let window = NSWindow(contentRect: .init(x: 0,y: 0,width: 900,height: 600), styleMask: [.titled], backing: .buffered, defer: false)
      let host = NSHostingView(rootView: WallProofView(model: model))
      window.contentView = host; window.makeKeyAndOrderFront(nil)
      let gif = CGImageDestinationCreateWithURL(directory.appendingPathComponent("glow-wall-contact.gif") as CFURL, UTType.gif.identifier as CFString, 100, nil)!
      CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
      for frame in 0..<100 {
        switch frame {
        case 8: model.target = CGPoint(x: 0.233,y: 0.5)
        case 27: model.target = CGPoint(x: 0.233,y: 0.03)
        case 45: model.target = CGPoint(x: 0.99,y: 0.45)
        case 64: model.target = CGPoint(x: 0.7,y: 0.99)
        case 82: model.target = CGPoint(x: 0.58,y: 0.5)
        default: break
        }
        try await Task.sleep(for: .milliseconds(55))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
          host.cacheDisplay(in: host.bounds, to: rep)
          if let image = rep.cgImage { CGImageDestinationAddImage(gif,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.055]] as CFDictionary) }
          if [6,24,42,61,79,99].contains(frame), let png = rep.representation(using: .png, properties: [:]) { try png.write(to: directory.appendingPathComponent("wall-\(frame).png")) }
        }
      }
      let ok = CGImageDestinationFinalize(gif)
      window.orderOut(nil)
      // Check the actual NavigationSplitView detail geometry, rather than a fixed sidebar width.
      let defaults = UserDefaults(suiteName: "BumpPump.WallGeometry."+UUID().uuidString)!
      let setup = SetupState(defaults: defaults)
      let geometry = WallGeometryModel()
      let workspace = NSHostingView(rootView: HomeWorkspace(state: HomeState(preload: true),setup: setup,preview: true)
        .onPreferenceChange(HomeGlowCollisionBounds.self) { geometry.bounds = $0 }
        .frame(width: 1000,height: 700))
      window.setContentSize(.init(width: 1000,height: 700)); window.contentView = workspace
      try await Task.sleep(for: .milliseconds(350))
      workspace.layoutSubtreeIfNeeded()
      let measured = geometry.bounds ?? .zero
      let measuredSidebar = measured.minX >= 200 && measured.width > 500
      let report: [String: Any] = ["ok":ok && measuredSidebar,"nativeRenderFrames":100,"actualDetailBounds":["x":measured.minX,"y":measured.minY,"width":measured.width,"height":measured.height],"sidebarGeometryMeasured":measuredSidebar,"personalDataRead":false,"externalRequests":0]
      try JSONSerialization.data(withJSONObject: report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("report.json"))
    } catch { try? String(describing:error).write(to: directory.appendingPathComponent("error.txt"),atomically:true,encoding:.utf8) }
    NSApp.terminate(nil)
  }
}
@MainActor private final class WallProofModel: ObservableObject { @Published var target = CGPoint(x:0.58,y:0.5) }
@MainActor private final class WallGeometryModel { var bounds: CGRect? }
private struct WallProofView: View {
  @ObservedObject var model: WallProofModel
  var body: some View {
    ZStack(alignment:.leading) {
      SetupPalette(dark:true).background
      HomePointerGlow(location:model.target,dark:true,active:true,reduced:false,collisionBounds:CGRect(x:210,y:0,width:690,height:600))
      Rectangle().fill(Color(hex:0x1C1D21)).frame(width:210)
      VStack(alignment:.leading,spacing:18) {
        Text("侧边栏").font(.system(size:20,weight:.medium))
        Text("接触边界时受压\n离开后恢复形状").font(.system(size:12)).foregroundStyle(.secondary)
      }.padding(28).frame(width:210,height:600,alignment:.topLeading)
      Rectangle().fill(Color.white.opacity(0.12)).frame(width:1).offset(x:210)
    }.frame(width:900,height:600).environment(\.colorScheme,.dark)
  }
}
