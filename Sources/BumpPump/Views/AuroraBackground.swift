import SwiftUI

/// A single low-frequency Canvas, not a stack of animated full-window blurs.
struct AuroraBackground: View {
  let dark: Bool
  let reducedMotion: Bool
  let active: Bool
  var fixedTime: Double?
  private let colors: [Color] = [Color(hex: 0x345CFF), Color(hex: 0x36CCCE), Color(hex: 0xA291FF), Color(hex: 0xF06C94), Color(hex: 0xF5AC74)]
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0/30, paused: reducedMotion || !active || fixedTime != nil)) { timeline in
      let t = fixedTime ?? (reducedMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
      Canvas { context, size in
        context.addFilter(.blur(radius: 52))
        for i in colors.indices {
          let phase = t * 0.22 + Double(i) * 1.43
          let x = size.width * (Double(i)/4 + sin(phase) * 0.13)
          let y = size.height * (0.95 + cos(phase * 0.83) * 0.12)
          let w = size.width * (0.53 + sin(phase*0.71)*0.09)
          let h = size.height * (1.05 + cos(phase*0.62)*0.17)
          let rect = CGRect(x: x-w/2, y: y-h/2, width: w, height: h)
          context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [colors[i].opacity(dark ? 0.46 : 0.32), colors[i].opacity(0)]),
            center: CGPoint(x: x,y: y), startRadius: 0, endRadius: w*0.54))
        }
      }
    }
    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.18), location: 0.25), .init(color: .black, location: 0.72)], startPoint: .top, endPoint: .bottom))
    .allowsHitTesting(false).accessibilityHidden(true)
  }
}
