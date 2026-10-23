import SwiftUI

struct HomeSidebar: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  let toggleSidebar: () -> Void
  @State private var foodExpanded = true
  @State private var strengthExpanded = false
  @State private var cardioExpanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // The trailing action shares the top row with native window controls,
      // while remaining to the right of their reserved leading area.
      HStack {
        Spacer(minLength: 0)
        Button(action: toggleSidebar) {
          Image(systemName: "sidebar.leading")
            .font(.system(size: 14, weight: .medium))
            .frame(width: 32, height: 32)
        }
        .modifier(AppGlassButton(circle: true))
        .environment(\.usesGlassControls, true)
        .accessibilityLabel("收起侧栏")
        .help("收起侧栏")
      }
      .padding(.horizontal, 20)
      .frame(height: 52)
      Label("泵碰", systemImage: "dumbbell")
        .font(.system(size: 20, weight: .medium))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
      List(selection: Binding<HomeDestination?>(get: { state.destination }, set: { if let value = $0 { state.select(value) } })) {
        Label("主页 · 概览", systemImage: "house").tag(HomeDestination.overview).padding(.vertical, 5)
        DisclosureGroup(isExpanded: $foodExpanded) {
          ForEach(DemoMealKind.allCases) { kind in Text(kind.rawValue).tag(HomeDestination.meal(kind)).padding(.vertical, 3) }
          Text("已知食物营养成分").tag(HomeDestination.foods).padding(.vertical, 3)
        } label: { Label("饮食", systemImage: "fork.knife").padding(.vertical, 5) }
        DisclosureGroup(isExpanded: $strengthExpanded) {
          ForEach(HomeDestination.strengthNames, id: \.self) { name in Text(name).tag(HomeDestination.strength(name)).padding(.vertical, 3) }
        } label: { Label("力量训练", systemImage: "dumbbell").padding(.vertical, 5) }
        DisclosureGroup(isExpanded: $cardioExpanded) {
          ForEach(HomeDestination.cardioNames, id: \.self) { name in Text(name).tag(HomeDestination.cardio(name)).padding(.vertical, 3) }
        } label: { Label("有氧训练", systemImage: "figure.run").padding(.vertical, 5) }
      }.listStyle(.sidebar).scrollContentBackground(.hidden).font(.system(size: 14))
      VStack(alignment: .leading, spacing: 16) {
        Divider().opacity(0.5)
        Button { state.showRecords = true } label: { Label("我的本机记录", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity, alignment: .leading) }.modifier(AppGlassButton()).frame(minHeight: 32)
        SettingsLink { Label("设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading) }
          .modifier(AppGlassButton()).frame(minHeight: 32)
      }.padding(20)
    }.ignoresSafeArea(.container, edges: .top).foregroundStyle(palette.foreground)
      .onChange(of: state.destination) { _, destination in
        withAnimation(.easeOut(duration: 0.2)) {
          switch destination { case .meal, .foods: foodExpanded = true; case .strength: strengthExpanded = true; case .cardio: cardioExpanded = true; default: break }
        }
      }
  }
}
