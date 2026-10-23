import SwiftUI

struct ImportedHistoryView: View {
  let entries: HomeDemoEntries
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var scheme
  @State private var table = "profile"
  @State private var query = ""
  private var palette: SetupPalette { .init(dark: scheme == .dark) }
  private var tables: [String] { (entries.sourceArchive ?? [:]).keys.sorted() }
  private var rows: [[String: String]] { (entries.sourceArchive?[table] ?? []).filter { query.isEmpty || $0.values.contains { $0.localizedCaseInsensitiveContains(query) } } }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack { Text("导入来源与档案").font(.system(size: 26, weight: .medium)); Spacer(); HomeIconButton(symbol: "xmark", label: "关闭导入来源") { dismiss() }.keyboardShortcut(.cancelAction) }
      Text("历史原文只读保留；日常修改在“我的本机记录”中进行，不改写原始来源。").font(.system(size: 12)).foregroundStyle(palette.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 15) {
          ForEach(entries.importNotes ?? [], id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(palette.secondary).lineSpacing(4) }
          Divider()
          Picker("来源表", selection: $table) { ForEach(tables, id: \.self) { Text($0 + " · \(entries.sourceArchive?[$0]?.count ?? 0) 条").tag($0) } }
          TextField("搜索来源内容", text: $query).textFieldStyle(.plain).modifier(FieldSurface(palette: palette)).accessibilityLabel("搜索导入来源")
          ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            DisclosureGroup(row["name"] ?? row["custom_name"] ?? row["id"] ?? row["key"] ?? "第 \(index+1) 条") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(row.keys.sorted(), id: \.self) { key in
                  VStack(alignment: .leading, spacing: 3) {
                    Text(key).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
                    Text(row[key] ?? "—").font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                  }
                }
              }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 6)
          }
        }
      }
    }.padding(30).frame(width: 760, height: 650).foregroundStyle(palette.foreground).background(palette.background).environment(\.usesGlassControls, true)
      .onAppear { if !tables.contains(table) { table = tables.first ?? "" } }
  }
}
