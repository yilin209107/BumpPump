import SwiftUI

struct SetupPalette {
  let dark: Bool
  var background: Color { Color(hex: dark ? 0x111214 : 0xF6F5F1) }
  var foreground: Color { Color(hex: dark ? 0xF2F1ED : 0x232427) }
  var secondary: Color { Color(hex: dark ? 0xACAEB4 : 0x61646B) }
  var surface: Color { Color(hex: dark ? 0x1C1D21 : 0xFEFDFA) }
  var line: Color { Color(hex: dark ? 0x45474D : 0xBABCC1) }
  var accent: Color { Color(hex: dark ? 0x8AB4FF : 0x245BD9) }
  var error: Color { Color(hex: dark ? 0xFFB3A8 : 0xB12F2B) }
  var success: Color { Color(hex: dark ? 0x16773E : 0x7DE5A6) }
}
extension Color {
  init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1) }
}
struct SetupField<Content: View>: View {
  let title: String
  let palette: SetupPalette
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.secondary)
      content.font(.system(size: 16)).foregroundStyle(palette.foreground)
    }
  }
}
struct FieldSurface: ViewModifier {
  let palette: SetupPalette
  func body(content: Content) -> some View {
    content.padding(.horizontal, 16).frame(minHeight: 48)
      .modifier(AppGlassSurface())
  }
}

/// The first-run flow keeps its original opaque, quiet controls.
struct SetupQuietButtonStyle: ButtonStyle {
  let palette: SetupPalette
  var strong = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(strong ? palette.foreground : palette.secondary)
      .opacity(configuration.isPressed ? 0.5 : 1)
      .contentShape(Rectangle())
  }
}

struct SetupFlatFieldSurface: ViewModifier {
  let palette: SetupPalette
  func body(content: Content) -> some View {
    content.padding(.horizontal, 16).frame(minHeight: 48)
      .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.line.opacity(0.7), lineWidth: 1))
  }
}
