import SwiftUI

/// Standard text editing inside the official SDK glass surface, scoped to the main column.
struct HomeWorkspaceGlassSearch:View {
  @Binding var text:String
  var submit:()->Void
  var body:some View {
    HStack(spacing:7) {
      Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
      TextField("搜索记录或食品",text:$text).textFieldStyle(.plain).onSubmit(submit)
        .accessibilityLabel("搜索记录或食品")
      if !text.isEmpty {Button{text=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}.buttonStyle(.plain).accessibilityLabel("清除搜索")}
    }.font(.system(size:13)).frame(height:22).padding(.horizontal,12).padding(.vertical,6)
      .modifier(AppGlassSurface(radius:18)).environment(\.usesGlassControls,true)
  }
}
