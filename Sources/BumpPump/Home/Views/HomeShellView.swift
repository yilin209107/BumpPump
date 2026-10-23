import SwiftUI

struct HomeShellView: View {
  @ObservedObject var setup: SetupState
  @StateObject private var ownedState: HomeState
  var preview = false
  init(setup: SetupState, injectedState: HomeState? = nil, preview: Bool = false) {
    self.setup = setup; self.preview = preview
    _ownedState = StateObject(wrappedValue: injectedState ?? HomeState(entryStore: preview || HomeChecks.output != nil || OnboardingChecks.output != nil ? nil : .local))
  }
  private var state: HomeState { ownedState }
  var body: some View { HomeWorkspace(state: state, setup: setup, preview: preview) }
}
struct HomeWorkspace: View {
  @ObservedObject var state: HomeState
  @ObservedObject var setup: SetupState
  var preview = false
  @Environment(\.accessibilityReduceMotion) private var reduced
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.scenePhase) private var scenePhase
  @State private var columns = NavigationSplitViewVisibility.all
  @State private var assistant = false
  @State private var workspaceWidth:CGFloat=1120
  @State private var columnsBeforeAssistant=NavigationSplitViewVisibility.all
  @State private var sidebarCollapsedForAssistant=false
  @State private var searchPresented = false
  @StateObject private var agent:FitnessAgentState
  init(state:HomeState,setup:SetupState,preview:Bool=false) {
    self.state=state;self.setup=setup;self.preview=preview
    _agent=StateObject(wrappedValue:FitnessAgentState(directory:preview ? nil:state.entryStore?.url.deletingLastPathComponent().appendingPathComponent("Assistant")))
  }
  @Environment(\.openSettings) private var openSettings
  var body: some View {
    let palette = setup.palette
    HomeAtmosphere(dark: setup.dark, reduced: reduced, fixedTime: preview ? 8 : nil) {
      HStack(spacing:0) {
      NavigationSplitView(columnVisibility: $columns) {
        HomeSidebar(state:state,palette:palette,toggleSidebar:{withAnimation(.easeInOut(duration:0.22)){columns = .detailOnly}})
          .background { Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .top) }
          .navigationSplitViewColumnWidth(min: 210, ideal: 228, max: 270)
      } detail: {
        VStack(spacing:0) {
          workspaceHeader(palette:palette)
          ZStack {
          if !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HomeSearchView(state: state, palette: palette).transition(.opacity)
          } else if state.isLoading {
            HomeLoadingView(palette: palette)
          } else {
            Group {
              switch state.destination {
              case .overview: HomeOverviewView(state: state, palette: palette, reduced: reduced)
              default: HomeCategoryView(state: state, palette: palette, reduced: reduced)
              }
            }.id(state.destination).transition(.opacity.combined(with: .offset(y: reduced ? 0 : 6)))
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().safeAreaPadding(.top, 12)
          .background { GeometryReader { geometry in
            Color.clear.preference(key: HomeGlowCollisionBounds.self, value: geometry.frame(in: .named("homeGlowSpace")))
          } }
          .animation(.easeInOut(duration: reduced ? 0.12 : 0.25), value: state.destination)
          .animation(.easeOut(duration: 0.24), value: state.isLoading)
        }
        // The header belongs to this column, rather than the window-wide toolbar.
        // Extending into the transparent titlebar avoids a second row of chrome.
        .ignoresSafeArea(.container, edges:.top)
        .navigationSplitViewColumnWidth(min:320,ideal:720,max:.infinity)
        .navigationTitle(state.query.isEmpty ? (state.destination == .overview ? "主页":state.destination.title) : "搜索")
        .modifier(HomeWorkspaceToolbarTitle())
      }.navigationSplitViewStyle(.balanced)
        .toolbar(removing:.sidebarToggle)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth:0,maxWidth:.infinity)
      if assistant {AssistantPanel(agent:agent,home:state,setup:setup){setAssistant(false)}.frame(width:min(390,max(320,workspaceWidth*0.34))).transition(.move(edge:.trailing).combined(with:.opacity))}
      }.background(WorkspaceWindowChrome())
      .background(AssistantLayoutProbe(open:assistant,panelWidth:min(390,max(320,workspaceWidth*0.34))))
      .onGeometryChange(for:CGFloat.self){$0.size.width}action:{width in
        workspaceWidth=width
        if assistant {adaptSidebarForAssistant()}
      }
    }.environment(\.usesGlassControls, false).ignoresSafeArea(edges: .top).foregroundStyle(palette.foreground).tint(palette.accent)
      .task { state.load(); if !preview && HomeChecks.output == nil && OnboardingChecks.output == nil { await state.loadPackagedFoods() } }
      .onChange(of: colorScheme, initial: true) { _, scheme in if !preview { setup.dark = scheme == .dark } }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active && !preview { state.refreshCalendar(); state.refreshLocalEntries() }
      }
      .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { tick in
        if scenePhase == .active && !preview { state.refreshCalendar(now: tick) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .newFitnessRecord)) { _ in if scenePhase == .active && state.entry == nil && !state.showRecords { state.beginContextEntry() } }
      .onReceive(NotificationCenter.default.publisher(for: .refreshFitnessRecords)) { _ in
        if scenePhase == .active { state.refreshCalendar(); state.refreshLocalEntries(); if !preview { Task { await state.loadPackagedFoods(force: true) } } }
      }
      .sheet(isPresented: $state.showRecords) { HomeRecordsView(state: state, palette: palette) }
      .sheet(item: $state.entry) { HomeEntryView(state: state, kind: $0, palette: palette) }
      .sheet(item: $state.detail) { HomeRecordSheet(record: $0, palette: palette) }
      .onReceive(NotificationCenter.default.publisher(for:.agentRecordsChanged)){_ in if state.entry == nil{state.refreshLocalEntries()} }
  }
  private func setAssistant(_ showing:Bool) {
    if showing {columnsBeforeAssistant=columns}
    withAnimation(.easeInOut(duration:reduced ? 0.12:0.36)) {
      assistant=showing
      if showing {adaptSidebarForAssistant()}
      else if sidebarCollapsedForAssistant {columns=columnsBeforeAssistant;sidebarCollapsedForAssistant=false}
    }
  }
  private func adaptSidebarForAssistant(){
    if workspaceWidth<1100 {
      if !sidebarCollapsedForAssistant {columns = .detailOnly;sidebarCollapsedForAssistant=true}
    }else if sidebarCollapsedForAssistant {columns=columnsBeforeAssistant;sidebarCollapsedForAssistant=false}
  }
  private var pageTitle:String {state.query.isEmpty ? (state.destination == .overview ? "主页":state.destination.title):"搜索"}
  private func submitSearch(){if let first=state.searchResults.first {state.selectSearchResult(first)}}
  private func workspaceHeader(palette:SetupPalette)->some View {
    GeometryReader {geometry in
      let compact=geometry.size.width < 680
      ZStack {
        Text(pageTitle).font(.system(size:13,weight:.medium)).lineLimit(1)
          .frame(maxWidth:max(100,geometry.size.width-200))
          .accessibilityAddTraits(.isHeader)
        HStack {
          if columns == .detailOnly {
            Button {withAnimation(.easeInOut(duration:0.22)){columns = .all}}label:{Image(systemName:"sidebar.leading").frame(width:26,height:26)}
              .modifier(AppGlassButton(circle:true)).environment(\.usesGlassControls,true).accessibilityLabel("展开侧栏")
          }
          Spacer(minLength:0)
        AppGlassGroup(spacing:12) { HStack(spacing:12) {
          if compact {
            Button{searchPresented.toggle()}label:{Image(systemName:"magnifyingglass").frame(width:26,height:26)}
              .modifier(AppGlassButton(circle:true)).keyboardShortcut("f",modifiers:.command)
              .accessibilityLabel("搜索记录或食品")
              .popover(isPresented:$searchPresented,arrowEdge:.bottom) {
                HomeWorkspaceGlassSearch(text:$state.query,submit:submitSearch)
                  .frame(width:260).padding(12)
              }
          } else {
            HomeWorkspaceGlassSearch(text:$state.query,submit:submitSearch)
              .frame(width:min(240,geometry.size.width*0.28))
          }
          Button {setAssistant(!assistant)} label: {
            Image(systemName:"bubble.left.and.bubble.right").frame(width:26,height:26)
          }.modifier(AppGlassButton(circle:true)).foregroundStyle(assistant ? palette.accent:palette.foreground)
            .accessibilityLabel(assistant ? "收起助理":"打开助理")
            .help(assistant ? "收起助理":"打开AI助理")
        }}.environment(\.usesGlassControls,true)
        }
        // This column reaches the window's left edge once the sidebar closes.
        // Reserve the traffic-light region before placing the reopen control.
        .padding(.leading, columns == .detailOnly ? 112 : 20)
        .padding(.trailing,20)
      }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }.frame(height:52)
  }

}
struct HomeLoadingView: View {
  let palette: SetupPalette
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack { ProgressView().controlSize(.small); Text("正在载入记录…").font(.system(size: 13)).foregroundStyle(palette.secondary) }
      RoundedRectangle(cornerRadius: 8).fill(palette.secondary.opacity(0.08)).frame(width: 230, height: 32)
      HStack { ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 16).fill(palette.secondary.opacity(0.065)).frame(height: 130) } }
      RoundedRectangle(cornerRadius: 16).fill(palette.secondary.opacity(0.04)).frame(height: 190)
      Spacer()
    }.padding(32).accessibilityElement(children: .ignore).accessibilityLabel("正在载入记录")
  }
}
struct HomeSearchView: View {
  @ObservedObject var state: HomeState
  let palette: SetupPalette
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("搜索结果").font(.system(size: 28, weight: .medium))
        Text("分类、" + HomeFormat.date(state.selectedDate) + "的饮食记录，以及预包装食品。").font(.system(size: 13)).foregroundStyle(palette.secondary)
        if state.searchResults.isEmpty {
          ContentUnavailableView.search(text: state.query).frame(maxWidth: .infinity).padding(.top, 45)
        } else {
          ForEach(state.searchResults) { result in
            Button { state.selectSearchResult(result) } label: {
              HStack {
                VStack(alignment: .leading, spacing: 6) { Text(result.title).font(.system(size: 16)); Text(result.subtitle).font(.system(size: 12)).foregroundStyle(palette.secondary) }
                Spacer(); Image(systemName: "arrow.up.left")
              }.padding(.vertical, 14).contentShape(Rectangle())
            }.modifier(AppGlassButton())
            Divider().opacity(0.4)
          }
        }
      }.padding(32).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
    }
  }
}

/// The title item kind was introduced a release after toolbar(removing:).
private struct HomeWorkspaceToolbarTitle:ViewModifier {
  @ViewBuilder func body(content:Content)->some View {
    if #available(macOS 15.0, *) {content.toolbar(removing:.title)}
    else {content}
  }
}
