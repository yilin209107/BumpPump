import SwiftUI

struct TutorialPage: View {
  @ObservedObject var state: SetupState
  let configureAI: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var step = 0
  private var titles: [String] { ["从一餐开始。", "记下每一次努力。", state.recordingMode == .ai ? "让助理搭把手。" : "按自己的节奏，开始。"] }
  private var icons: [String] { ["fork.knife", "dumbbell", state.recordingMode == .ai ? "bubble.left.and.bubble.right" : "square.and.pencil"] }
  private var detail: String {
    switch step {
    case 0: return "记录吃了什么、吃了多少。\n你可以选择告诉助理，也可以选择手动填写。"
    case 1: return "留下每次的运动数据，你会看到自己的进步。"
    default: return state.recordingMode == .ai
      ? "用自然语言描述饮食和训练，或与助理讨论计划。\nAI 参与整理时，记得核对记录再确认。"
      : "你选择了手动记录模式，AI 功能保持关闭。\n先把习惯养起来，之后随时可以连接助理。"
    }
  }
  var body: some View {
    let palette = state.palette
    VStack(spacing: 0) {
      Spacer(minLength: 24)
      Group {
        if state.tutorialCompleted {
          VStack(spacing: 24) {
            Image(systemName: "checkmark.circle").font(.system(size: 52, weight: .ultraLight)).foregroundStyle(palette.accent)
            Text("准备好了。").font(.system(size: 38, weight: .medium)).tracking(-1)
            Text("教程已完成 · " + (state.recordingMode == .ai ? "AI 助理模式" : "手动记录模式"))
              .font(.system(size: 15)).foregroundStyle(palette.secondary)
          }
        } else {
          VStack(spacing: 24) {
            Image(systemName: icons[step]).font(.system(size: 42, weight: .ultraLight)).frame(height: 60).accessibilityHidden(true)
            Text(titles[step]).font(.system(size: 38, weight: .medium)).tracking(-1)
            Text(detail).font(.system(size: 16)).lineSpacing(9).multilineTextAlignment(.center).foregroundStyle(palette.secondary)
            Text(state.recordingMode == .ai ? "已连接 AI · " + state.provider.name : "手动模式 · 无需 API Key")
              .font(.system(size: 12)).foregroundStyle(palette.secondary).padding(.top, 12)
          }.id(step).transition(.opacity)
        }
      }.frame(maxWidth: 650).frame(maxHeight: .infinity)
      if !state.tutorialCompleted {
        HStack(spacing: 14) {
          ForEach(0..<3) { index in
            Button { changeStep(index) } label: {
              Circle().fill(index == step ? palette.foreground : palette.secondary.opacity(0.35)).frame(width: 6, height: 6).frame(width: 32, height: 32)
            }.buttonStyle(SetupQuietButtonStyle(palette: palette)).accessibilityLabel("教程第\(index+1)步").accessibilityAddTraits(index == step ? .isSelected : [])
          }
        }.padding(.bottom, 25)
      }
      HStack {
        Button(state.tutorialCompleted ? "重新查看教程" : (step == 0 ? "配置 AI" : "上一步")) {
          if state.tutorialCompleted { state.tutorialCompleted = false; changeStep(0) }
          else if step == 0 { configureAI() } else { changeStep(step-1) }
        }.buttonStyle(SetupQuietButtonStyle(palette: palette)).font(.system(size: 13)).frame(minHeight: 44)
        Spacer()
        if state.tutorialCompleted {
          Button("调整 API 配置", action: configureAI).buttonStyle(SetupQuietButtonStyle(palette: palette)).font(.system(size: 13)).frame(minHeight: 44)
        } else {
          ForwardArrow(palette: palette, label: step == 2 ? "完成教程" : "教程下一步") {
            if step == 2 { withAnimation(.easeOut(duration: 0.3)) { state.finishTutorial() } }
            else { changeStep(step+1) }
          }
        }
      }.frame(maxWidth: 500).padding(.bottom, 32)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  private func changeStep(_ index: Int) { withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.25)) { step = index } }
}
