import SwiftUI

private struct GlassControlsKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
  var usesGlassControls: Bool {
    get { self[GlassControlsKey.self] }
    set { self[GlassControlsKey.self] = newValue }
  }
}
/// Glass belongs to setup and secondary editing surfaces; the workspace stays quiet.
struct AppGlassButton: ViewModifier {
  var prominent = false
  var tint: Color? = nil
  var circle = false
  @Environment(\.usesGlassControls) private var glass
  @ViewBuilder func body(content: Content) -> some View {
    if !glass {
      content.buttonStyle(HomeQuietButtonStyle(tint: tint))
    } else if #available(macOS 26.0, *) {
      if circle { styled(content).buttonBorderShape(.circle) }
      else { styled(content) }
    } else {
      if prominent { content.buttonStyle(.borderedProminent).tint(tint) }
      else { content.buttonStyle(.bordered).tint(tint) }
    }
  }
  @available(macOS 26.0, *) @ViewBuilder private func styled(_ content: Content) -> some View {
    if prominent { content.buttonStyle(.glassProminent).tint(tint) }
    else { content.buttonStyle(.glass).tint(tint) }
  }
}
private struct HomeQuietButtonStyle: ButtonStyle {
  var tint: Color?
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(tint ?? .primary).opacity(configuration.isPressed ? 0.55 : 1).contentShape(Rectangle())
  }
}
struct AppGlassGroup<Content: View>: View {
  var spacing: CGFloat = 16
  @ViewBuilder var content: Content
  @Environment(\.usesGlassControls) private var glass
  var body: some View {
    if #available(macOS 26.0, *), glass { GlassEffectContainer(spacing: spacing) { content } }
    else { content }
  }
}
struct AppGlassSurface: ViewModifier {
  var radius: CGFloat = 12
  @Environment(\.usesGlassControls) private var glass
  @Environment(\.colorScheme) private var scheme
  @ViewBuilder func body(content: Content) -> some View {
    if !glass {
      let palette = SetupPalette(dark: scheme == .dark)
      content.background(palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(palette.line.opacity(0.25), lineWidth: 1))
    } else if #available(macOS 26.0, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius)) }
    else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius)) }
  }
}
