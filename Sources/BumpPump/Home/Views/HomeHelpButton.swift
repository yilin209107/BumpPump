import SwiftUI

/// Keeps explanatory copy available on demand without crowding the record itself.
struct HomeHelpButton: View {
  let title: String
  let message: String
  @State private var showing = false
  var body: some View {
    Button { showing.toggle() } label: {
      Image(systemName: "questionmark.circle")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.blue)
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .environment(\.usesGlassControls, false)
    .accessibilityLabel(title + "说明")
    .accessibilityValue(showing ? "已展开" : "已收起")
    .help("查看" + title + "说明")
    .popover(isPresented: $showing, arrowEdge: .bottom) {
      VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        Text(message).font(.system(size: 14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      }
      .padding(20).frame(width: 320, alignment: .leading)
      .onExitCommand { showing = false }
    }
  }
}

struct HomeLabeledField<Content: View>: View {
  let title: String
  let palette: SetupPalette
  var help = ""
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 7) {
        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.secondary)
        if !help.isEmpty { HomeHelpButton(title: title, message: help) }
      }
      content.font(.system(size: 16)).foregroundStyle(palette.foreground)
    }
  }
}
