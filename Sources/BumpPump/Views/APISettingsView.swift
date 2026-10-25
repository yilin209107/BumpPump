import SwiftUI

struct APISettingsView: View {
  let configurationChanged: () -> Void
  var preview = false
  @StateObject private var state = SetupState(page: .api)
  @StateObject private var motion = SetupMotion()
  @State private var saved = false
  @Environment(\.colorScheme) private var colorScheme
  var body: some View {
    Group {
      if saved {
        VStack(spacing: 24) {
          Image(systemName: "checkmark.circle").font(.system(size: 52, weight: .ultraLight)).accessibilityHidden(true)
          Text("设置已保存。").font(.system(size: 34, weight: .medium))
          Text(state.recordingMode == .ai ? "下次会自动读取本机保存的 API Key。" : "已切换到手动记录模式。")
            .foregroundStyle(state.palette.secondary)
          Button("继续调整") { state.connectionPhase = .idle; saved = false }
            .modifier(AppGlassButton()).frame(minHeight: 44)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
          .foregroundStyle(state.palette.foreground).background(state.palette.background)
      } else {
        SetupFlowView(state: state, motion: motion, preview: preview, configurationOnly: true) {
          configurationChanged()
          withAnimation(.easeOut(duration: 0.25)) { saved = true }
        }
      }
    }.frame(minWidth: 760, minHeight: 640).frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear { state.restoreSelection(); state.page = .api; saved = false }
      .appOnChange(of: colorScheme, initial: true) { _, scheme in state.dark = scheme == .dark }
  }
}
