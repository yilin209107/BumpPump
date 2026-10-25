import SwiftUI

struct APISetupPage: View {
  @ObservedObject var state: SetupState
  @ObservedObject var motion: SetupMotion
  var preview: Bool
  var compact = false
  var configurationOnly = false
  let continueAction: () -> Void
  let skipAction: () -> Void
  let cancelAction: () -> Void
  @State private var revealKey = false
  @FocusState private var keyFocused: Bool
  var body: some View {
    let palette = state.palette
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          Image(systemName: "key.horizontal").font(.system(size: compact ? 28 : 34, weight: .light))
            .frame(height: compact ? 34 : 42).padding(.bottom, compact ? 12 : 20).accessibilityHidden(true)
          Text("配置您的 API Key")
            .font(.system(size: compact ? 30 : 34, weight: .medium)).tracking(-0.8)
          Text("选择一个你喜欢的AI，成为你的助理。\n你可以和他聊天、询问问题，或者让他来帮你记录、制作计划")
            .font(.system(size: compact ? 13 : 14)).lineSpacing(6).multilineTextAlignment(.center)
            .foregroundStyle(palette.secondary).padding(.top, compact ? 8 : 12)
          fields(palette).padding(.top, compact ? 22 : 30).disabled(state.saving)
          if let error = state.error {
            Label(error, systemImage: "exclamationmark.circle")
              .font(.system(size: 13)).foregroundStyle(palette.error)
              .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
              .accessibilityAddTraits(.updatesFrequently)
          }
          HStack(spacing: 6) {
            Image(systemName: "lock").accessibilityHidden(true)
            Text("API Key 在本机加密保存，下次自动读取。")
            Spacer()
            if let url = URL(string: state.provider.docs), !state.provider.docs.isEmpty {
              Link("官方文档 ↗", destination: url).foregroundStyle(palette.accent)
            }
          }.font(.system(size: 11)).foregroundStyle(palette.secondary).padding(.top, 18)
          Text("常用模型依据官方目录整理 · 2026.10.22")
            .font(.system(size: 10)).foregroundStyle(palette.secondary.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }.frame(maxWidth: 500).padding(.horizontal, 8).padding(.top, compact ? 8 : 24).padding(.bottom, compact ? 10 : 18)
          .frame(maxWidth: .infinity)
      }.scrollIndicators(.visible)
      Text("测试会发送一条简短请求，可能产生少量 API 费用。")
        .font(.system(size: 11)).foregroundStyle(palette.foreground.opacity(0.85))
        .frame(maxWidth: 500, alignment: .leading).padding(.top, 12)
      HStack {
        if state.saving {
          Button("取消测试", action: cancelAction).keyboardShortcut(.cancelAction)
            .font(.system(size: 13)).buttonStyle(SetupQuietButtonStyle(palette: palette)).frame(minHeight: 44)
        } else {
          Button(configurationOnly ? "改用手动记录" : "先用手动记录") { skipAction() }
            .font(.system(size: 13)).buttonStyle(SetupQuietButtonStyle(palette: palette)).frame(minHeight: 44)
        }
        Spacer()
        if state.saving {
          ProgressView().controlSize(.small).padding(.trailing, 10)
          Text("正在测试连接…").font(.system(size: 14)).accessibilityAddTraits(.updatesFrequently)
        } else {
          Text(configurationOnly ? "测试并保存" : "测试并继续").font(.system(size: 14)).foregroundStyle(palette.foreground).padding(.trailing, 12)
          ForwardArrow(palette: palette, opacity: motion.iconOpacity, label: configurationOnly ? "测试 API 并保存设置" : "测试 API，成功后保存并继续", action: continueAction)
        }
      }.frame(maxWidth: 500).padding(.top, 12).padding(.bottom, 24)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .task(id: state.provider.id) { if !preview { await state.loadKeyIfNeeded() } }
      .appOnChange(of: state.error) { _, error in if error != nil && state.apiKey.isEmpty { keyFocused = true } }
  }
  @ViewBuilder private func fields(_ palette: SetupPalette) -> some View {
    VStack(spacing: compact ? 14 : 20) {
      SetupField(title: "API 服务提供商", palette: palette) {
        SetupChoice(palette: palette, label: state.provider.name, accessibilityTitle: "API 服务提供商") {
          ForEach(APIProvider.all) { item in
            Button {
              state.selectProvider(item)
              NotificationCenter.default.post(name: .setupChoiceSelected, object: nil)
            } label: {
              HStack {
                Text(item.name); Spacer()
                if item.id == state.provider.id { Image(systemName: "checkmark") }
              }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(SetupQuietButtonStyle(palette: palette)).font(.system(size: 14))
          }
        }

      }
      if state.provider.id == "qwen" || state.provider.id == "kimi" {
        SetupField(title: "服务地区 · 与创建密钥的平台一致", palette: palette) {
          SetupChoice(palette: palette, label: regionTitle(state.region), accessibilityTitle: "API 服务地区") {
            ForEach(state.provider.id == "qwen" ? ["china", "singapore", "us", "hongkong"] : ["china", "global"], id: \.self) { region in
              Button {
                state.region = region
                NotificationCenter.default.post(name: .setupChoiceSelected, object: nil)
              } label: {
                HStack { Text(regionTitle(region)); Spacer(); if state.region == region { Image(systemName: "checkmark") } }.frame(minHeight: 32)
              }.buttonStyle(SetupQuietButtonStyle(palette: palette))
            }
          }
        }
      }
      if state.provider.id == "custom" {
        SetupField(title: "API 地址 · 兼容 OpenAI Chat Completions 的 Base URL", palette: palette) {
          TextField("https://…", text: $state.endpoint).textFieldStyle(.plain)
            .modifier(SetupFlatFieldSurface(palette: palette)).accessibilityLabel("自定义 API HTTPS 地址")
        }
      }
      SetupField(title: "API Key", palette: palette) {
        HStack(spacing: 8) {
          Group {
            if revealKey { TextField("粘贴您的 API Key", text: $state.apiKey) }
            else { SecureField("粘贴您的 API Key", text: $state.apiKey) }
          }.textFieldStyle(.plain).focused($keyFocused).accessibilityLabel("API Key")
            .onSubmit { if state.validateAPI() { continueAction() } }
          Button { revealKey.toggle(); keyFocused = true } label: {
            Image(systemName: revealKey ? "eye.slash" : "eye").font(.system(size: 15)).frame(width: 32, height: 36)
          }.buttonStyle(SetupQuietButtonStyle(palette: palette)).accessibilityLabel(revealKey ? "隐藏 API Key" : "显示 API Key")
        }.modifier(SetupFlatFieldSurface(palette: palette))
      }
      SetupField(title: "模型", palette: palette) {
        if state.customModel {
          HStack {
            TextField("填写模型 ID", text: $state.model).textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).accessibilityLabel("自定义模型 ID")
            if !state.provider.models.isEmpty {
              Button("候选列表") { state.customModel = false; state.model = state.provider.models[0] }
                .font(.system(size: 11)).buttonStyle(SetupQuietButtonStyle(palette: palette))
            }
          }.modifier(SetupFlatFieldSurface(palette: palette))
        } else {
          SetupChoice(palette: palette, label: state.model, accessibilityTitle: "选择模型", monospaced: true) {
            ForEach(state.provider.modelOptions) { option in
              Button {
                state.model = option.id
                NotificationCenter.default.post(name: .setupChoiceSelected, object: nil)
              } label: {
                HStack(alignment: .center, spacing: 12) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).font(.system(size: 13, weight: .medium))
                    Text(option.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.secondary)
                    Text(option.hint).font(.system(size: 10)).foregroundStyle(palette.secondary)
                  }
                  Spacer(minLength: 4)
                  if option.id == state.model { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
              }.buttonStyle(SetupQuietButtonStyle(palette: palette))
            }
            Divider()
            Button("输入其他模型 ID…") {
              state.customModel = true; state.model = ""
              NotificationCenter.default.post(name: .setupChoiceSelected, object: nil)
            }.buttonStyle(SetupQuietButtonStyle(palette: palette)).font(.system(size: 13)).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
          }

        }
      }
    }
  }
  private func regionTitle(_ region: String) -> String {
    switch region {
    case "singapore": return "新加坡"
    case "us": return "美国 · 弗吉尼亚"
    case "hongkong": return "中国香港"
    case "global": return "国际站 · moonshot.ai"
    default: return state.provider.id == "kimi" ? "中国站 · moonshot.cn" : "中国内地 · 北京"
    }
  }
}
