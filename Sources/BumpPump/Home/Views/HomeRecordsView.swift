import SwiftUI

struct HomeRecordsView: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduced
  @State private var removed = false
  @State private var filter = "全部"
  @State private var query = ""
  @State private var editing: HomeLocalRecord?
  @State private var newKind: HomeEntryKind?
  @State private var error: String?
  @State private var lastRemoved: HomeLocalRecord?
  private var records: [HomeLocalRecord] {
    (removed ? Array(state.removedRecords.reversed()) : state.localRecords).filter {
      (filter == "全部" || $0.kind.rawValue == filter) && (query.isEmpty || ($0.title + $0.category + HomeFormat.date($0.date, pattern: "yyyy-MM-dd")).localizedCaseInsensitiveContains(query))
    }
  }
  var body: some View {
    ZStack {
      palette.background
      VStack { Spacer(); AuroraBackground(dark: palette.dark, reducedMotion: reduced, active: scenePhase == .active).frame(height: 240).opacity(0.5) }.allowsHitTesting(false)
      VStack(alignment: .leading, spacing: 20) {
        header
        Picker("记录状态", selection: $removed) {
          Text("本机记录 · \(state.localRecords.count)").tag(false)
          Text("最近移除 · \(state.removedRecords.count)").tag(true)
        }.pickerStyle(.segmented)
        HStack(spacing: 14) {
          TextField("搜索名称、分类或日期", text: $query).textFieldStyle(.plain).modifier(FieldSurface(palette: palette)).accessibilityLabel("搜索本机记录")
          Picker("记录类型", selection: $filter) { Text("全部").tag("全部"); Text("饮食").tag("food"); Text("运动").tag("activity"); Text("体重").tag("weight") }.frame(width: 90)
        }
        if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(palette.error) }
        if records.isEmpty {
          ContentUnavailableView(removed ? "这里没有已移除的记录" : "还没有匹配的本机记录", systemImage: removed ? "arrow.uturn.backward" : "square.and.pencil", description: Text(removed ? "移除的记录会保留在这里，可以随时恢复。" : "你的记录会出现在这里。导入记录和手动记录都可以在这里修改。" )).frame(maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(records) { record in
                HStack(spacing: 18) {
                  VStack(alignment: .leading, spacing: 7) {
                    Text(record.title).font(.system(size: 16, weight: .medium))
                    Text(HomeFormat.date(record.date, pattern: "yyyy年M月d日") + " · " + record.category).font(.system(size: 11)).foregroundStyle(palette.secondary)
                    Text(record.summary).font(.system(size: 12)).foregroundStyle(palette.secondary)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                  if removed {
                    Button("恢复") { restore(record) }.modifier(AppGlassButton(tint: .blue)).accessibilityLabel("恢复" + record.title)
                  } else {
                    Button("修改") { editing = record }.modifier(AppGlassButton()).accessibilityLabel("修改" + record.title)
                    Button { remove(record) } label: { Image(systemName: "trash").frame(width: 28, height: 30) }.modifier(AppGlassButton(tint: .red)).accessibilityLabel("移除" + record.title)
                  }
                }.padding(.vertical, 17)
                Divider().opacity(0.3)
              }
            }
          }
        }
        HStack(spacing: 15) {
          if let lastRemoved, state.removedRecords.contains(where: { $0.id == lastRemoved.id }) {
            Text("已移除“\(lastRemoved.title)”").font(.system(size: 12)).lineLimit(1)
            Button("撤销") { restore(lastRemoved) }.modifier(AppGlassButton())
          }
          Spacer()
        }.frame(minHeight: 32)
      }.padding(28)
    }.frame(width: 700, height: 630).foregroundStyle(palette.foreground).environment(\.usesGlassControls, true)
      .sheet(item: $editing) { record in
        HomeEntryView(state: state, kind: record.kind, palette: palette, draft: HomeEntryDraft(record: record, goal: state.energyGoal))
      }
      .sheet(item: $newKind) { kind in HomeEntryView(state: state, kind: kind, palette: palette, draft: HomeEntryDraft(kind: kind, date: state.selectedDate, goal: state.energyGoal)) }
  }
  private var header: some View {
    HStack(spacing: 18) {
      HStack(spacing: 7) {
        Text("我的本机记录").font(.system(size: 27, weight: .medium))
        HomeHelpButton(title: "我的本机记录", message: "记录保存在本机，导入来源随记录保留。可按类型、名称或日期查找，修改后会同步更新图表。移除后记录会留在“最近移除”中，可以恢复；刚移除时也可点击撤销。")
      }
      Spacer()
      Menu { Button("饮食") { newKind = .food }; Button("运动") { newKind = .activity }; Button("体重") { newKind = .weight } } label: { Label("新增", systemImage: "plus") }
        .menuStyle(.borderlessButton).modifier(AppGlassButton(tint: .blue)).fixedSize()
      HomeIconButton(symbol: "xmark", label: "关闭本机记录") { dismiss() }.keyboardShortcut(.cancelAction)
    }
  }
  private func remove(_ record: HomeLocalRecord) {
    do { try state.moveToTrash(record); error = nil; lastRemoved = record }
    catch { self.error = error.localizedDescription }
  }
  private func restore(_ record: HomeLocalRecord) {
    do { try state.restoreRecord(record); error = nil }
    catch { self.error = error.localizedDescription }
  }
}
