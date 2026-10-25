import SwiftUI
import AppKit
import Charts

extension View {
  func appOnChange<Value:Equatable>(of value:Value,initial:Bool=false,_ action:@escaping(Value,Value)->Void)->some View {
    modifier(AppChangeObserver(value:value,initial:initial,action:action))
  }
  @ViewBuilder func appDefaultScrollAnchor(_ anchor:UnitPoint)->some View {
    if #available(macOS 14,*) {defaultScrollAnchor(anchor)}else{self}
  }
  @ViewBuilder func appScrollClipDisabled()->some View {
    if #available(macOS 14,*) {scrollClipDisabled()}else{self}
  }
  @ViewBuilder func appSafeAreaPadding(_ edges:Edge.Set,_ length:CGFloat)->some View {
    if #available(macOS 14,*) {safeAreaPadding(edges,length)}else{padding(edges,length)}
  }
  @ViewBuilder func appNumericTransition(value:Double)->some View {
    if #available(macOS 14,*) {contentTransition(.numericText(value:value))}else{self}
  }
  @ViewBuilder func appRemoveSidebarToolbar()->some View {
    if #available(macOS 14,*) {toolbar(removing:.sidebarToggle)}else{self}
  }
}
private struct AppChangeObserver<Value:Equatable>:ViewModifier {
  let value:Value
  let initial:Bool
  let action:(Value,Value)->Void
  @State private var previous:Value
  @State private var appeared=false
  init(value:Value,initial:Bool,action:@escaping(Value,Value)->Void){
    self.value=value;self.initial=initial;self.action=action;_previous=State(initialValue:value)
  }
  @ViewBuilder func body(content:Content)->some View {
    if #available(macOS 14,*) {content.onChange(of:value,initial:initial,action)}
    else {
      content.onAppear {
        guard !appeared else{return};appeared=true;previous=value
        if initial{action(value,value)}
      }.onChange(of:value){next in let old=previous;previous=next;action(old,next)}
    }
  }
}
extension Animation {
  static func appSmooth(duration:Double)->Animation {
    if #available(macOS 14,*) {return .smooth(duration:duration)}
    return .easeInOut(duration:duration)
  }
  static func appSpring(duration:Double,bounce:Double=0)->Animation {
    if #available(macOS 14,*) {return .spring(duration:duration,bounce:bounce)}
    return .spring(response:duration,dampingFraction:max(0.65,1-bounce))
  }
}
extension ChartProxy {
  var appPlotFrame:Anchor<CGRect>? {
    if #available(macOS 14,*) {return plotFrame}
    return plotAreaFrame
  }
}

struct AppEmptyState:View {
  let title:String
  let systemImage:String
  let description:Text
  init(_ title:String,systemImage:String,description:Text){self.title=title;self.systemImage=systemImage;self.description=description}
  static func search(text:String)->Self {.init("没有找到结果",systemImage:"magnifyingglass",description:Text("没有与“\(text)”匹配的记录。"))}
  @ViewBuilder var body:some View {
    if #available(macOS 14,*) {ContentUnavailableView(title,systemImage:systemImage,description:description)}
    else {
      VStack(spacing:12){Image(systemName:systemImage).font(.system(size:32)).foregroundStyle(.secondary);Text(title).font(.headline);description.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)}.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
  }
}

private struct AppOpenSettingsKey:EnvironmentKey {
  static let defaultValue:()->Void = {NSApp.sendAction(Selector(("showSettingsWindow:")),to:nil,from:nil)}
}
extension EnvironmentValues {
  var appOpenSettings:()->Void {get{self[AppOpenSettingsKey.self]}set{self[AppOpenSettingsKey.self]=newValue}}
}
struct AppSettingsCompatibility:ViewModifier {
  @ViewBuilder func body(content:Content)->some View {
    if #available(macOS 14,*) {content.modifier(ModernSettingsOpener())}else{content}
  }
}
@available(macOS 14,*) private struct ModernSettingsOpener:ViewModifier {
  @Environment(\.openSettings) private var openSettings
  func body(content:Content)->some View {content.environment(\.appOpenSettings,{openSettings()})}
}

extension View {
  @ViewBuilder func appRoundedButtonBorder(radius:CGFloat)->some View {
    if #available(macOS 14,*) {buttonBorderShape(.roundedRectangle(radius:radius))}else{self}
  }
}
struct AppSettingsLink<Label:View>:View {
  @Environment(\.appOpenSettings) private var openSettings
  @ViewBuilder var label:Label
  @ViewBuilder var body:some View {
    if #available(macOS 14,*) {SettingsLink{label}}
    else {Button(action:openSettings){label}}
  }
}
