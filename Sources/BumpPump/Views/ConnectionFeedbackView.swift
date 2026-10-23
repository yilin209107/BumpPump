import SwiftUI

struct ConnectionFeedbackView: View {
  let success: Bool
  let palette: SetupPalette
  let reducedMotion: Bool
  let iconOpacity: Double
  let action: () -> Void
  @State private var visible = false
  var body: some View {
    Group {
      if success {
        Button(action: action) { symbol }
          .buttonStyle(ArrowPressStyle()).keyboardShortcut(.return, modifiers: [])
      } else { symbol }
    }
    .opacity(visible ? 1 : 0)
    .scaleEffect(reducedMotion ? 1 : (visible ? 1 : 0.88))
    .accessibilityLabel(success ? "API 连接成功，继续教程" : "API 测试失败，请查看错误提示")
    .onAppear { withAnimation(.easeOut(duration: reducedMotion ? 0.15 : 0.35).delay(reducedMotion ? 0 : 0.2)) { visible = true } }
  }
  private var symbol: some View {
    Image(systemName: success ? "checkmark" : "xmark")
      .font(.system(size: 36, weight: .medium))
      .foregroundStyle(success ? palette.success : palette.error).opacity(iconOpacity)
      .frame(width: 88, height: 88)
      .background(success ? palette.foreground : palette.surface, in: Circle())
  }
}
