import AppKit
import SwiftUI

struct SetupFlowView: View {
  @ObservedObject var state: SetupState
  @ObservedObject var motion: SetupMotion
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @State private var arrived = false
  @State private var showingHelp = false
  @State private var verificationTask: Task<Void, Never>?
  @State private var currentSize = CGSize.zero
  var preview = false
  var fixedTime: Double?
  var configurationOnly = false
  var configurationFinished: () -> Void = {}
  private var showingFeedback: Bool { state.connectionPhase == .success || state.connectionPhase == .failure }
  var body: some View {
    GeometryReader { geo in
      let palette = state.palette
      ZStack {
        palette.background
        VStack {
          Spacer(minLength: 0)
          AuroraBackground(dark: state.dark, reducedMotion: reduceMotion, active: scenePhase == .active || preview, fixedTime: fixedTime)
            .frame(height: min(310, geo.size.height*0.42))
            .opacity(state.page == .welcome ? 0 : 0.65)
        }.animation(.easeInOut(duration: reduceMotion ? 0.15 : 1.3), value: state.page)
        VStack(spacing: 0) {
          header(palette: palette, size: geo.size)
          Group {
            switch state.page {
            case .welcome:
              WelcomePage(palette: palette, arrived: arrived, iconOpacity: motion.iconOpacity) { advance(.api, size: geo.size) }
            case .api:
              APISetupPage(state: state, motion: motion, preview: preview, compact: geo.size.height < 720, configurationOnly: configurationOnly, continueAction: {
                startConnection(size: geo.size)
              }, skipAction: {
                state.useManualMode()
                if configurationOnly { configurationFinished() }
                else { motion.advance(to: .preferences, state: state, size: geo.size, reduced: true) }
              }, cancelAction: {
                verificationTask?.cancel(); state.cancelTest()
              })
            case .preferences:
              TutorialPage(state: state) {
                state.tutorialCompleted = false
                motion.advance(to: .api, state: state, size: geo.size, reduced: true)
              }
            }
          }.id(state.page)
        }
        .opacity(motion.pageOpacity * (state.connectionPhase == .success ? 0 : (state.connectionPhase == .failure ? 0.22 : 1)))
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: state.connectionPhase)
        .allowsHitTesting(!motion.busy && !showingFeedback)
        .disabled(motion.busy || showingFeedback)
        .accessibilityHidden(motion.busy || showingFeedback)
        .padding(.horizontal, geo.size.width < 900 ? 28 : 42).padding(.top, 32)
        if showingFeedback {
          ConnectionFeedbackView(success: state.connectionPhase == .success, palette: palette, reducedMotion: reduceMotion, iconOpacity: motion.iconOpacity) {
            finishConnection(size: geo.size)
          }
          .opacity(motion.pageOpacity)
          .allowsHitTesting(state.connectionPhase == .success && !motion.busy)
          .disabled(motion.busy)
          .transition(.opacity)
        }
        Circle().fill(palette.foreground)
          .frame(width: motion.radius*2, height: motion.radius*2)
          .position(motion.rippleCenter).opacity(motion.rippleOpacity)
          .allowsHitTesting(false).accessibilityHidden(true)
      }
      .coordinateSpace(name: "setupRoot")
      .onPreferenceChange(ContinueBounds.self) { motion.buttonRect = $0 }
      .onChange(of: geo.size, initial: true) { _, size in currentSize = size }
      .clipped().foregroundStyle(palette.foreground)
      .background(palette.background.ignoresSafeArea())
      .background(WindowShake(trigger: state.shakeID, reducedMotion: reduceMotion))
      .onAppear {
        if preview || reduceMotion { arrived = true }
        else { withAnimation(.easeOut(duration: 0.85).delay(0.16)) { arrived = true } }
      }
      .onDisappear { verificationTask?.cancel(); state.cancelTest(); motion.cancel() }
    }
    .preferredColorScheme(preview ? (state.dark ? .dark : .light) : nil)
    .onChange(of: colorScheme, initial: true) { _, scheme in if !preview { state.dark = scheme == .dark } }
    .tint(state.palette.accent)
    .sheet(isPresented: $showingHelp) { APIHelpSheet(palette: state.palette).environment(\.usesGlassControls, false) }
    .environment(\.usesGlassControls, false)
  }
  private func advance(_ page: SetupPage, size: CGSize) {
    motion.advance(to: page, state: state, size: size, reduced: reduceMotion)
  }
  private func startConnection(size: CGSize) {
    guard !state.saving, !showingFeedback, !motion.busy else { return }
    verificationTask = Task {
      let connected = await state.testAndSaveAPI()
      guard !Task.isCancelled else { return }
      if connected {
        announce("API 连接成功")
        do { try await Task.sleep(for: .milliseconds(reduceMotion ? 1000 : 1500)) } catch { return }
        finishConnection(size: currentSize == .zero ? size : currentSize)
      } else if state.connectionPhase == .failure {
        announce("API 测试失败。" + (state.error ?? "请检查配置"))
        do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
        if state.connectionPhase == .failure { withAnimation(.easeOut(duration: 0.2)) { state.connectionPhase = .idle } }
      }
    }
  }
  private func finishConnection(size: CGSize) {
    guard state.connectionPhase == .success, !motion.busy else { return }
    if configurationOnly { configurationFinished(); return }
    motion.advance(to: .preferences, state: state, size: size, reduced: reduceMotion,
      origin: CGRect(x: size.width/2-44, y: size.height/2-44, width: 88, height: 88))
  }
  private func announce(_ text: String) {
    NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
      userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }
  private func header(palette: SetupPalette, size: CGSize) -> some View {
    HStack {
      Group {
        if state.page != .welcome && !configurationOnly {
          Button {
            motion.advance(to: state.page == .preferences ? .api : .welcome, state: state, size: size, reduced: true)
          } label: {
            HStack(spacing: 8) { Image(systemName: "arrow.left"); Text("返回") }
              .font(.system(size: 13)).frame(minWidth: 64, minHeight: 44)
          }.buttonStyle(SetupQuietButtonStyle(palette: palette)).keyboardShortcut(.leftArrow, modifiers: .command)
        } else { Color.clear.frame(height: 44) }
      }.frame(width: 92, alignment: .leading)
      Spacer()
      if state.page != .welcome && !configurationOnly {
        Text(String(format: "%02d", state.page.rawValue+1) + "  /  03")
          .font(.system(size: 12, design: .monospaced)).tracking(2).foregroundStyle(palette.secondary)
      }
      Spacer()
      Group {
        if state.page == .api {
          Button { showingHelp = true } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44)
          }.buttonStyle(SetupQuietButtonStyle(palette: palette))
            .accessibilityLabel("API Key 开通与充值帮助").help("第一次使用 API？查看分步指南")
        } else { Color.clear.frame(width: 44, height: 44) }
      }.frame(width: 92, alignment: .trailing)
    }.disabled(motion.busy || state.saving).padding(.bottom, 10)
  }
}
struct ForwardArrow: View {
  let palette: SetupPalette
  var opacity = 1.0
  var label = "继续"
  let action: () -> Void
  @Environment(\.usesGlassControls) private var glass
  @State private var hover = false
  var body: some View {
    Group {
      if glass { glassArrow }
      else { originalArrow }
    }
  }
  private var originalArrow: some View {
    Button(action: action) {
      Image(systemName: "arrow.right").font(.system(size: 23, weight: .medium))
        .foregroundStyle(palette.background).opacity(opacity)
        .frame(width: 56, height: 56)
        .background(palette.foreground, in: Circle())
        .overlay(Circle().strokeBorder(palette.accent.opacity(hover ? 0.65 : 0), lineWidth: 3))
        .background(GeometryReader { proxy in
          Color.clear.preference(key: ContinueBounds.self, value: proxy.frame(in: .named("setupRoot")))
        })
    }.buttonStyle(ArrowPressStyle())
      .onHover { hover = $0 }.animation(.easeOut(duration: 0.18), value: hover)
      .accessibilityLabel(label).help(label).keyboardShortcut(.return, modifiers: [])
  }
  private var glassArrow: some View {
    Button(action: action) {
      Image(systemName: "arrow.right").font(.system(size: 23, weight: .medium))
        .foregroundStyle(palette.background).opacity(opacity)
        .frame(width: 56, height: 56)
    }.modifier(AppGlassButton(prominent: true, tint: palette.foreground, circle: true))
      .background(GeometryReader { proxy in
        Color.clear.preference(key: ContinueBounds.self, value: proxy.frame(in: .named("setupRoot")))
      })
      .onHover { hover = $0 }.animation(.easeOut(duration: 0.18), value: hover)
      .accessibilityLabel(label).help(label).keyboardShortcut(.return, modifiers: [])
  }

}
struct ArrowPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
      .scaleEffect(configuration.isPressed ? 0.95 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
