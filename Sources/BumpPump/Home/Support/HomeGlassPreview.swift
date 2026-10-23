import SwiftUI

/// Isolated visual fixtures: no persistent records, SQL connections or model requests.
struct HomeGlassPreview: View {
  static var enabled: Bool { ["--glass-preview", "--workspace-preview", "--records-preview", "--about-preview", "--data-preview", "--settings-preview"].contains { CommandLine.arguments.contains($0) } }
  @StateObject private var state: HomeState
  @StateObject private var setup: SetupState
  private let exportStore: HomeDemoEntryStore
  private let previewDefaults: UserDefaults
  private var dark: Bool { !CommandLine.arguments.contains("--light") }
  init() {
    let state = HomeState(preload: true)
    try? state.addFood(.init(date: state.anchor, kind: .lunch, time: "12:30", name: "隔离预览食物", amount: "1 份", nutrition: .init(protein: 10, carbs: 20, fat: 5)))
    try? state.addActivity(.init(date: state.anchor, title: "跑步", category: "有氧训练", time: "19:00", minutes: 30, kcal: nil, muscles: [], notes: "预览记录"))
    try? state.addWeight(.init(date: state.anchor, jin: 121, conditions: "隔离预览"))
    state.packagedFoods = [.init(id: "preview-label", fields: ["name": "示例预包装食品", "brand": "示例品牌", "basis": "100g", "kcal": "100", "source": "label_text"])]
    state.catalogLoaded = true
    let exportStore = HomeDemoEntryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("FitnessExportPreview." + UUID().uuidString).appendingPathComponent("entries.json"))
    if CommandLine.arguments.contains("--data-preview") || CommandLine.arguments.contains("--settings-preview") { try? exportStore.save(state.entries) }
    self.exportStore = exportStore
    _state = StateObject(wrappedValue: state)
    let defaults = UserDefaults(suiteName: "BumpPump.Preview." + UUID().uuidString)!
    previewDefaults = defaults
    let setup = SetupState(defaults: defaults); setup.dark = !CommandLine.arguments.contains("--light")
    _setup = StateObject(wrappedValue: setup)
  }
  var body: some View {
    ZStack {
      SetupPalette(dark: dark).background
      if CommandLine.arguments.contains("--workspace-preview") { HomeWorkspace(state: state, setup: setup, preview: true) }
      else if CommandLine.arguments.contains("--records-preview") { HomeRecordsView(state: state, palette: SetupPalette(dark: dark)) }
      else if CommandLine.arguments.contains("--about-preview") { AppAboutView(defaults: previewDefaults) }
      else if CommandLine.arguments.contains("--data-preview") { LocalDataSettingsView(store: exportStore) }
      else if CommandLine.arguments.contains("--settings-preview") { AppSettingsView(setup: setup, apiPreview: true, dataStore: exportStore) }
      else { HomeEntryView(state: state, kind: .energy, palette: SetupPalette(dark: dark), preview: true) }
    }.preferredColorScheme(dark ? .dark : .light).navigationTitle("隔离界面检查")
  }
}
