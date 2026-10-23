import SwiftUI
import AppKit

/// The workspace owns a column-scoped header. Remove the otherwise empty native
/// toolbar so it cannot intercept clicks through that header; keep native window controls.
struct WorkspaceWindowChrome:NSViewRepresentable {
  func makeNSView(context:Context)->Probe{Probe()}
  func updateNSView(_ view:Probe,context:Context){view.configure()}
  final class Probe:NSView {
    private var toolbarObservation:NSKeyValueObservation?
    override func viewDidMoveToWindow(){
      super.viewDidMoveToWindow();toolbarObservation=nil
      if let window {toolbarObservation=window.observe(\.toolbar,options:[.new]){[weak self] window,_ in
        if window.toolbar != nil{self?.configure()}
      }}
      configure()
    }
    func configure(){DispatchQueue.main.async{[weak self] in
      guard let window=self?.window else{return}
      window.toolbar=nil
      window.titlebarAppearsTransparent=true
      window.titleVisibility = .hidden
      window.styleMask.insert(.fullSizeContentView)
      window.isMovableByWindowBackground=false
      for kind in [NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton]{window.standardWindowButton(kind)?.isHidden=false}
    }}
  }
}
