import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
  @ObservedObject var setup: SetupState
  var apiPreview = false
  var dataStore = HomeDemoEntryStore.local
  @AppPreference("BumpPump.settingsTab") private var tab = "ai"
  var body: some View {
    TabView(selection: $tab) {
      APISettingsView(configurationChanged: { setup.restoreSelection() }, preview: apiPreview).tabItem { Label("AI 配置", systemImage: "key.horizontal") }.tag("ai")
      LocalDataSettingsView(store: dataStore).tabItem { Label("本机数据", systemImage: "externaldrive") }.tag("data")
      AppAboutView().tabItem { Label("版本与更新", systemImage: "info.circle") }.tag("about")
    }.frame(width: 900, height: 790).environment(\.usesGlassControls, true)
  }
}
struct LocalDataSettingsView: View {
  var store = HomeDemoEntryStore.local
  @Environment(\.colorScheme) private var scheme
  @State private var summary = "正在读取…"
  @State private var error: String?
  @State private var exporting = false
  @State private var hasData = false
  @State private var exportStatus: String?
  @State private var imported: HomeDemoEntries?
  private var palette: SetupPalette { .init(dark: scheme == .dark) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        Label("本机数据", systemImage: "externaldrive").font(.system(size: 29, weight: .medium))
        Text("你的饮食、训练、测量和食品标签保存在这台 Mac。").font(.system(size: 14)).foregroundStyle(palette.secondary).lineSpacing(6)
        VStack(alignment: .leading, spacing: 12) {
          Text("我的记录").font(.system(size: 18, weight: .medium))
          VStack(alignment: .leading, spacing: 18) {
            Text(summary).font(.system(size: 14))
            Text("修改、移除与恢复：主窗口左下角 → 我的本机记录。").font(.system(size: 12)).foregroundStyle(palette.secondary)
            HStack(spacing: 16) {
              Button("导出记录备份…") { prepareExport() }.modifier(AppGlassButton()).disabled(!hasData || exporting)
              Button("在 Finder 中显示") { let directory = store.url.deletingLastPathComponent(); NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path) }.modifier(AppGlassButton()).disabled(!FileManager.default.fileExists(atPath: store.url.deletingLastPathComponent().path))
              Button("刷新") { refresh() }.modifier(AppGlassButton())
              Button("导入来源与档案…") { do { imported = try store.read() } catch { self.error = "无法读取导入来源。" } }.modifier(AppGlassButton())
            }
            Text("备份含本机记录、最近移除及热量目标，不包含 API Key。完整备份也包含食品库与导入来源。").font(.system(size: 12)).foregroundStyle(palette.secondary).lineSpacing(5)
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        Divider().opacity(0.3)
        VStack(alignment: .leading, spacing: 12) {
          Text("预包装食品库").font(.system(size: 18, weight: .medium))
          Text("导入的食品标签已保存在 App 本机数据中。标签与历史份量计算均保留来源。").font(.system(size: 14)).foregroundStyle(palette.secondary).lineSpacing(6).padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        if !hasData && error == nil { Text("添加本机记录或设置目标后，就可以导出备份。").font(.system(size: 12)).foregroundStyle(palette.secondary) }
        if let exportStatus { Text(exportStatus).font(.system(size: 13)) }
        if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(palette.error) }
      }.padding(40).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
    }.background(palette.background).onAppear { refresh() }.sheet(isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } })) { if let imported { ImportedHistoryView(entries: imported) } }
  }

  private func refresh() {
    do { let entries = try store.read(); hasData = !entries.foods.isEmpty || !entries.activities.isEmpty || !entries.weights.isEmpty || !(entries.trash ?? []).isEmpty || entries.energyGoal != nil || !(entries.foodLibrary ?? []).isEmpty || !(entries.sourceArchive ?? [:]).isEmpty; summary = "饮食 \(entries.foods.count) 条 · 运动 \(entries.activities.count) 条 · 体重 \(entries.weights.count) 条 · 最近移除 \(entries.trash?.count ?? 0) 条"; error = nil }
    catch { hasData = false; summary = "记录暂时无法读取，原文件已保留。"; self.error = "请检查本机记录文件；App 不会用空白数据覆盖它。" }
  }
  private func prepareExport() {
    guard !exporting else { return }
    do {
      let data = try HomeRecordBackup.encode(store.read())
      error = nil; exportStatus = nil; exporting = true
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.json]
      panel.nameFieldStringValue = "BumpPump-本机记录-" + HomeFormat.date(Date(), pattern: "yyyy-MM-dd") + ".json"
      panel.canCreateDirectories = true
      let completion: (NSApplication.ModalResponse) -> Void = { response in
        guard response == .OK, let destination = panel.url else { exporting = false; return }
        Task { @MainActor in
          do {
            try await Task.detached(priority: .userInitiated) {
              let access = destination.startAccessingSecurityScopedResource()
              defer { if access { destination.stopAccessingSecurityScopedResource() } }
              try data.write(to: destination, options: .atomic)
              try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }.value
            exportStatus = "备份已导出。"
          } catch { self.error = "未能导出，请重新选择保存位置。" }
          exporting = false
        }
      }
      if let window = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
      else { panel.begin(completionHandler: completion) }
    } catch { self.error = "无法读取记录，未生成空白备份。" }
  }

}
struct AppAboutView: View {
  @Environment(\.colorScheme) private var scheme
  @AppPreference private var repository: String
  init(defaults: UserDefaults = .standard) { _repository = AppPreference(wrappedValue: "yilin209107/BumpPump", "BumpPump.updateRepository", store: defaults) }
  @State private var result: AppReleaseInfo?
  @State private var message = ""
  @State private var checking = false
  @State private var request: Task<Void, Never>?
  private var palette: SetupPalette { .init(dark: scheme == .dark) }
  private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版" }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().scaledToFit().frame(width: 76, height: 76).accessibilityHidden(true)
        Text("泵碰 · BumpPump").font(.system(size: 32, weight: .medium))
        Text("版本 " + version + " · macOS 原生预览版").font(.system(size: 14)).foregroundStyle(palette.secondary)
        Text("支持本机记录、统计与助理对话。发送消息时，会将本次对话、附件及助理查询的相关记录交给你选择的AI服务商。图片识别需所选模型支持；API费用由服务商收取。").font(.system(size: 14)).foregroundStyle(palette.secondary).lineSpacing(6)
        Divider().opacity(0.3)
        SetupField(title: "此项目的 GitHub 发布仓库", palette: palette) {
          TextField("owner/repository 或 GitHub 仓库网址", text: $repository).textFieldStyle(.plain).modifier(FieldSurface(palette: palette)).accessibilityLabel("GitHub 发布仓库")
        }
        if !repository.isEmpty && AppReleaseChecker.repository(repository) == nil {
          Text("请填写 owner/repository，或完整的 GitHub 仓库网址。").font(.system(size: 12)).foregroundStyle(palette.error)
        }
        Text("发布后填写实际仓库，点击时才会检查最新正式版本。发现新版后打开 GitHub 发行页，由你下载替换 App；本机记录会保留。").font(.system(size: 13)).foregroundStyle(palette.secondary).lineSpacing(6)
        HStack(spacing: 15) {
          if checking { ProgressView().controlSize(.small); Button("取消检查") { request?.cancel() }.modifier(AppGlassButton()) }
          else { Button("检查新版本") { check() }.modifier(AppGlassButton()).disabled(AppReleaseChecker.repository(repository) == nil) }
          if let result { Link("查看发行页 ↗", destination: result.url).modifier(AppGlassButton()) }
        }
        if !message.isEmpty { Text(message).font(.system(size: 14)).foregroundStyle(palette.foreground).accessibilityAddTraits(.updatesFrequently) }
      }.padding(40).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
    }.background(palette.background)
      .appOnChange(of: repository) { _, _ in request?.cancel(); result = nil; message = "" }
      .onDisappear { request?.cancel() }
  }
  private func check() {
    guard !checking else { return }
    checking = true; result = nil; message = "正在查询 GitHub 正式发行版…"
    request = Task {
      defer { checking = false }
      do {
        let release = try await AppReleaseChecker.check(repository: repository, currentVersion: version)
        try Task.checkCancellation(); result = release
        switch release.newer {
        case true: message = "发现新版本：" + release.tag
        case false:
          if let current = AppSemanticVersion(version), let latest = AppSemanticVersion(release.tag), latest < current {
            message = "本机是较新的预览版本，GitHub 正式版为 " + release.tag + "。"
          } else { message = "已经是最新版本（" + release.tag + "）。" }
        case nil: message = "最新发行标签：" + release.tag + "。标签格式无法自动比较，可打开发行页查看。"
        }
      } catch is CancellationError { message = "检查已取消。" }
      catch let error as URLError where error.code == .cancelled { message = "检查已取消。" }
      catch { message = (error as? AppUpdateError)?.localizedDescription ?? "暂时无法连接 GitHub，请检查网络后重试。" }
    }
  }
}
