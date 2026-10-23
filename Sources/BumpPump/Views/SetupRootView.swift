import SwiftUI

struct SetupRootView: View {
  @ObservedObject var state: SetupState
  @ObservedObject var motion: SetupMotion
  @Environment(\.colorScheme) private var colorScheme
  var preview = false
  @State private var animationsVisible=true
  var body: some View {
    Group {
      if HomeRingChecks.output != nil || HomeFluidWallChecks.output != nil { Color.clear }
      else if HomeGlassPreview.enabled { HomeGlassPreview() }
      else if state.presentsOnboarding && !CommandLine.arguments.contains("--home-demo") && HomeChecks.output == nil {
        SetupFlowView(state: state, motion: motion, preview: preview)
      } else {
        HomeShellView(setup: state, preview: preview)
      }
    }.background(AppWindowActivity{animationsVisible=$0})
      .environment(\.appAnimationsVisible,preview || animationsVisible)
  }
}
