import SwiftUI
import AppKit

private struct AppAnimationsVisibleKey:EnvironmentKey{static let defaultValue=true}
extension EnvironmentValues {
  var appAnimationsVisible:Bool{get{self[AppAnimationsVisibleKey.self]}set{self[AppAnimationsVisibleKey.self]=newValue}}
}
/// Observes only this app's own window; stops decorative work when it is hidden.
struct AppWindowActivity:NSViewRepresentable {
  var changed:(Bool)->Void
  func makeCoordinator()->Coordinator{Coordinator(changed:changed)}
  func makeNSView(context:Context)->Probe{let view=Probe();view.attached={ [weak c=context.coordinator] window in c?.observe(window)};return view}
  func updateNSView(_ view:Probe,context:Context){context.coordinator.changed=changed}
  final class Probe:NSView{var attached:((NSWindow?)->Void)?;override func viewDidMoveToWindow(){super.viewDidMoveToWindow();attached?(window)}}
  final class Coordinator {
    weak var window:NSWindow?
    var changed:(Bool)->Void
    var tokens:[NSObjectProtocol]=[]
    var last:Bool?
    init(changed:@escaping(Bool)->Void){self.changed=changed}
    deinit{tokens.forEach{NotificationCenter.default.removeObserver($0)}}
    func observe(_ window:NSWindow?){
      tokens.forEach{NotificationCenter.default.removeObserver($0)};tokens=[];self.window=window
      guard let window else{return}
      for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification] {
        tokens.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self] _ in self?.publish()})
      }
      for name in [NSApplication.didBecomeActiveNotification,NSApplication.didResignActiveNotification] {
        tokens.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.publish()})
      }
      publish()
    }
    func publish(){guard let window else{return};let value=NSApp.isActive && window.occlusionState.contains(.visible) && !window.isMiniaturized
      guard value != last else{return};last=value;DispatchQueue.main.async{[weak self] in self?.changed(value)}
    }
  }
}
