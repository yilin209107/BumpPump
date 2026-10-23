import SwiftUI
import AppKit

struct WelcomePage: View {
  let palette: SetupPalette
  let arrived: Bool
  let iconOpacity: Double
  let continueAction: () -> Void
  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 40)
      VStack(spacing: 24) {
        WelcomeMark(palette: palette, arrived: arrived).frame(width: 76, height: 76).padding(.bottom, 14)
        Text("泵碰，我们开始吧。")
          .font(.system(size: 46, weight: .medium)).tracking(-1.8)
          .foregroundStyle(palette.foreground)
        Text("让我们帮助你记录每一餐、每一次训练\n准备好改变你自己了吗？")
          .font(.system(size: 18, weight: .regular)).lineSpacing(8)
          .multilineTextAlignment(.center).foregroundStyle(palette.secondary)
      }.opacity(arrived ? 1 : 0).offset(y: arrived ? 0 : 10)
      Spacer().frame(height: 76)
      VStack(spacing: 18) {
        ForwardArrow(palette: palette, opacity: iconOpacity, label: "开始配置", action: continueAction)
      }.opacity(arrived ? 1 : 0).offset(y: arrived ? 0 : 12)
      Spacer(minLength: 60)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
struct WelcomeMark: View {
  let palette: SetupPalette
  let arrived: Bool
  var body: some View {
    Image(nsImage: NSApplication.shared.applicationIconImage)
      .resizable().scaledToFit()
      .opacity(arrived ? 1 : 0)
      .accessibilityHidden(true)
  }
}
