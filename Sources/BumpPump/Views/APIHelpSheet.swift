import SwiftUI

struct APIHelpSheet: View {
  let palette: SetupPalette
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("第一次使用 API？").font(.system(size: 23, weight: .medium))
        Spacer()
        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
          .buttonStyle(SetupQuietButtonStyle(palette: palette)).keyboardShortcut(.cancelAction).accessibilityLabel("关闭 API 指南")
      }.padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 12)
      ScrollView {
        VStack(alignment: .leading, spacing: 25) {
          Text("API Key 就像一把钥匙，让这个 App 能使用你选择的 AI 服务。\n下面以 DeepSeek 为例，带你完成第一次连接。")
            .font(.system(size: 14)).lineSpacing(7).foregroundStyle(palette.secondary)
          HStack(spacing: 20) {
            Link("开发者平台 ↗", destination: URL(string: "https://platform.deepseek.com/")!)
            Link("官方 API 文档 ↗", destination: URL(string: "https://api-docs.deepseek.com/zh-cn/")!)
          }.font(.system(size: 13, weight: .medium)).foregroundStyle(palette.accent)
          step(1, title: "注册并登录开发者平台") {
            Text("点击上方“开发者平台”，在 DeepSeek 官方网站完成注册或登录。开发者平台用于管理密钥、API 余额和用量。")
          }
          step(2, title: "为 API 账户准备额度") {
            Text("在开发者平台查看余额；需要时进入充值页面，按页面提示选择金额和支付方式。API 会按实际调用量计费，金额与支付方式以官方页面为准。初次体验可以先少量充值。")
            Link("打开 DeepSeek 充值入口 ↗", destination: URL(string: "https://platform.deepseek.com/top_up")!).foregroundStyle(palette.accent)
          }
          step(3, title: "创建自己的 API Key") {
            Text("在平台中进入“API keys / API 密钥”，创建一个新密钥，可以命名为“健身助理”。复制生成的完整 Key，妥善保管，不要公开分享。")
            Link("打开 API Key 管理 ↗", destination: URL(string: "https://platform.deepseek.com/api_keys")!).foregroundStyle(palette.accent)
          }
          step(4, title: "回到 App，粘贴密钥并选择模型") {
            Text("服务商选择 DeepSeek，把刚复制的 Key 粘贴到输入框，再选择一个模型。初次使用可从 DeepSeek V4.1 Flash 开始；列表中的准确模型 ID 为 deepseek-flash。Key 会在测试成功后由 App 在本机加密保存，下次自动读取。")
          }
          step(5, title: "点击“测试并继续”") {
            Text("App 会发送一句简短问候，确认密钥与所选模型能够使用，可能产生少量 API 费用。出现绿色对勾后会进入教程。若失败，请根据提示检查密钥、余额、模型权限或网络，再手动重试。")
            Text("暂时不想使用 AI？关闭本指南，选择“先用手动记录”。之后仍可重新配置 AI。")
          }
          Divider().overlay(palette.line)
          Text("其他提供商也与上述步骤类似，同时，本应用不提供LLM（大语言模型）的生成服务，也不收取AI生成所需费用。")
            .font(.system(size: 13)).lineSpacing(7).foregroundStyle(palette.secondary)
        }.padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 30)
      }.scrollIndicators(.visible)
    }
    .foregroundStyle(palette.foreground).background(palette.background)
    .frame(width: 650, height: 620)
  }
  private func step<Content: View>(_ number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Text(String(number)).font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(palette.accent).frame(width: 27, height: 27)
        .background(palette.accent.opacity(0.1), in: Circle()).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 9) {
        Text(title).font(.system(size: 16, weight: .medium)).accessibilityAddTraits(.isHeader)
        content().font(.system(size: 13)).lineSpacing(6).foregroundStyle(palette.secondary).textSelection(.enabled)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
