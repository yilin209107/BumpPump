import SwiftUI

extension Notification.Name { static let setupChoiceSelected = Notification.Name("FitnessSetup.choiceSelected") }
/// SwiftUI popover keeps the entire custom field label visible on macOS.
struct SetupChoice<Options: View>: View {
  let palette: SetupPalette
  let label: String
  let accessibilityTitle: String
  var monospaced = false
  @ViewBuilder var options: Options
  @State private var presented = false
  @State private var hover = false
  var body: some View {
    Button { presented.toggle() } label: {
      HStack {
        Text(label).font(.system(size: monospaced ? 14 : 16, design: monospaced ? .monospaced : .default))
          .lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: 12)
        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.secondary)
      }.frame(maxWidth: .infinity).modifier(SetupFlatFieldSurface(palette: palette))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.accent.opacity(hover ? 0.6 : 0),lineWidth: 1))
    }.buttonStyle(.plain)
      .onHover { hover = $0 }
      .accessibilityLabel(accessibilityTitle + "，" + label)
      .accessibilityValue(presented ? "已展开" : "已折叠")
      .popover(isPresented: $presented, arrowEdge: .trailing) {
        VStack(alignment: .leading, spacing: 4) { options }
          .padding(14).frame(minWidth: 260, maxWidth: 370)
          .foregroundStyle(palette.foreground)
          .preferredColorScheme(palette.dark ? .dark : .light)
      }
      .onReceive(NotificationCenter.default.publisher(for: .setupChoiceSelected)) { _ in presented = false }
  }
}
