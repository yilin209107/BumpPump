import SwiftUI

struct HomeGlowCollisionBounds: PreferenceKey {
  static var defaultValue: CGRect? = nil
  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { if let next = nextValue(), next.width > 0, next.height > 0 { value = next } }
}

/// Pointer events live outside statistics state; the fluid solver only redraws its Canvas.
struct HomeAtmosphere<Content: View>: View {
  let dark: Bool
  let reduced: Bool
  var fixedTime: Double?
  @ViewBuilder var content: Content
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.appAnimationsVisible) private var animationsVisible
  @State private var location = CGPoint(x: 0.6, y: 0.4)
  @State private var present = false
  @State private var insideAssistant = false
  @State private var collisionBounds: CGRect?
  @State private var lastUpdate = Date.distantPast
  var body: some View {
    GeometryReader { geo in
      ZStack {
        SetupPalette(dark: dark).background
        HomePointerGlow(location: location, dark: dark, active: scenePhase == .active && animationsVisible && !insideAssistant, reduced: reduced, fixedTime: fixedTime, collisionBounds: collisionBounds.map { CGRect(x: $0.minX, y: 0, width: max(20,min(geo.size.width,$0.maxX)-$0.minX), height: geo.size.height) })
          .opacity(insideAssistant ? 0 : present ? 1 : 0.6).allowsHitTesting(false).accessibilityHidden(true)
        content
      }.coordinateSpace(name: "homeGlowSpace")
      .onPreferenceChange(HomeGlowCollisionBounds.self) { collisionBounds = $0 }
      .onContinuousHover { phase in
        guard !reduced, fixedTime == nil else { return }
        switch phase {
        case .active(let point):
          let now = Date()
          guard now.timeIntervalSince(lastUpdate) > 1.0/30 else { return }
          lastUpdate = now
          let inAssistant = collisionBounds.map { $0.maxX < geo.size.width-20 && point.x >= $0.maxX } ?? false
          if insideAssistant != inAssistant {withAnimation(.easeOut(duration:0.35)){insideAssistant=inAssistant}}
          guard !inAssistant else{return}
          location = CGPoint(x: min(1, max(0, point.x / max(geo.size.width, 1))), y: min(1, max(0, point.y / max(geo.size.height, 1))))
          withAnimation(.easeOut(duration: 0.8)) { present = true }
        case .ended: withAnimation(.easeOut(duration: 1.2)) { present = false }
        }
      }.clipped()
    }
  }
}
struct HomePointerGlow: View {
  var location: CGPoint
  let dark: Bool
  let active: Bool
  let reduced: Bool
  var fixedTime: Double?
  var collisionBounds: CGRect? = nil
  @State private var renderer = HomeFluidRenderer()
  private let colors: [Color] = [Color(hex: 0x4E86F4), Color(hex: 0x53D6D2), Color(hex: 0xA48AF6), Color(hex: 0xF189AE), Color(hex: 0xF1C77D)]
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0/30, paused: !active || reduced || fixedTime != nil)) { timeline in
      let time = fixedTime ?? timeline.date.timeIntervalSinceReferenceDate
      Canvas(rendersAsynchronously: false) { context, size in
        let window = CGRect(origin: .zero, size: size)
        let requested = (collisionBounds ?? window).intersection(window)
        let bounds = requested.isNull || requested.width < 20 || requested.height < 20 ? window : requested
        let blobs = renderer.frame(time: time, target: location, size: size, bounds: bounds, still: reduced || fixedTime != nil)
        context.clip(to: Path(bounds))
        // One closed surface and one shared opacity: colours cannot become separate islands.
        let path = Self.outline(HomeFluidSurface.outline(blobs, bounds: bounds), bounds: bounds)
        let colorBounds = path.boundingRect
        func paint(_ layer: inout GraphicsContext) {
          layer.blendMode = .normal
          layer.opacity = 1
          layer.clip(to: path)
          layer.fill(path, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: colorBounds.minX, y: colorBounds.maxY), endPoint: CGPoint(x: colorBounds.maxX, y: colorBounds.minY)))
          for (index, blob) in blobs.enumerated() {
            let center = CGPoint(x: blob.center.x, y: blob.center.y)
            layer.fill(path, with: .radialGradient(Gradient(colors: [colors[index].opacity(0.9), colors[index].opacity(0)]), center: center, startRadius: 0, endRadius: blob.radius*2.4))
          }
        }
        if dark { context.blendMode = .plusLighter }
        var halo = context
        halo.opacity = dark ? 0.20 : 0.10
        halo.addFilter(.blur(radius: min(size.width, size.height)*0.054))
        halo.drawLayer { layer in paint(&layer) }
        var body = context
        body.opacity = dark ? 0.23 : 0.18
        body.addFilter(.blur(radius: min(size.width, size.height)*0.013))
        body.drawLayer { layer in paint(&layer) }
      }
    }
  }
  private static func outline(_ points: [CGPoint], bounds: CGRect) -> Path {
    var path = Path()
    guard points.count > 3 else { return path }
    func confined(_ point: CGPoint) -> CGPoint { CGPoint(x: min(bounds.maxX,max(bounds.minX,point.x)), y: min(bounds.maxY,max(bounds.minY,point.y))) }
    path.move(to: points[0])
    for index in points.indices {
      let p0 = points[(index+points.count-1)%points.count], p1 = points[index]
      let p2 = points[(index+1)%points.count], p3 = points[(index+2)%points.count]
      path.addCurve(to: p2, control1: confined(CGPoint(x: p1.x+(p2.x-p0.x)/6, y: p1.y+(p2.y-p0.y)/6)), control2: confined(CGPoint(x: p2.x-(p3.x-p1.x)/6, y: p2.y-(p3.y-p1.y)/6)))
    }
    path.closeSubpath()
    return path
  }
}
private final class HomeFluidRenderer {
  private let lock = NSLock()
  private var physics = HomeFluidPhysics()
  private var previous: Double?
  private var stillTarget: CGPoint?
  private var stillSize = CGSize.zero
  private var stillBounds = CGRect.zero
  func frame(time: Double, target: CGPoint, size: CGSize, bounds: CGRect, still: Bool) -> [HomeFluidBlob] {
    lock.lock(); defer { lock.unlock() }
    if still {
      if stillTarget != target || stillSize != size || stillBounds != bounds {
        physics = HomeFluidPhysics()
        for _ in 0..<100 { physics.advance(target: target, size: size, elapsed: 1.0/30, bounds: bounds) }
        stillTarget = target; stillSize = size; stillBounds = bounds
      }
    } else {
      let elapsed = previous.map { time-$0 } ?? 1.0/30
      physics.advance(target: target, size: size, elapsed: elapsed, bounds: bounds)
    }
    previous = time
    return physics.blobs
  }
}
