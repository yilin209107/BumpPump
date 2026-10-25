import SwiftUI
import AppKit

/// The workspace owns a column-scoped header. Remove the otherwise empty native
/// toolbar so it cannot intercept clicks through that header; keep native window controls.
struct WorkspaceWindowChrome:NSViewRepresentable {
  func makeNSView(context:Context)->Probe{Probe()}
  func updateNSView(_ view:Probe,context:Context){view.configure()}
  final class Probe:NSView {
    private var configurePending=false
    private var toolbarObservation:NSKeyValueObservation?
    override func viewDidMoveToWindow(){
      super.viewDidMoveToWindow();toolbarObservation=nil
      if let window {toolbarObservation=window.observe(\.toolbar,options:[.new]){[weak self] window,_ in
        if window.toolbar != nil{self?.configure()}
      }}
      configure()
    }
    func configure(){
      guard !configurePending else{return}
      configurePending=true
      DispatchQueue.main.async{[weak self] in
      guard let self else{return}
      self.configurePending=false
      guard let window=self.window else{return}
      if window.toolbar != nil {window.toolbar=nil}
      if !window.titlebarAppearsTransparent {window.titlebarAppearsTransparent=true}
      if window.titleVisibility != .hidden {window.titleVisibility = .hidden}
      if !window.styleMask.contains(.fullSizeContentView) {window.styleMask.insert(.fullSizeContentView)}
      if window.isMovableByWindowBackground {window.isMovableByWindowBackground=false}
      for kind in [NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton]{if let button=window.standardWindowButton(kind),button.isHidden {button.isHidden=false}}
    }}
  }
}
