import SwiftUI
import AppKit

/// Opt-in local layout diagnostics for isolated UI checks. Never records content.
struct AssistantLayoutProbe:NSViewRepresentable {
  var open:Bool
  var panelWidth:CGFloat
  func makeNSView(context:Context)->NSView{NSView()}
  func updateNSView(_ view:NSView,context:Context){
    let args=CommandLine.arguments
    guard args.contains("--isolated-records"),let i=args.firstIndex(of:"--assistant-layout-check"),args.count>i+1 else{return}
    let url=URL(fileURLWithPath:args[i+1]),open=open,panelWidth=panelWidth
    DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[weak view] in
      guard let window=view?.window,let root=window.contentView?.superview else{return}
      let point=NSPoint(x:root.bounds.width-(open ? panelWidth:0)-38,y:root.bounds.height-26)
      let hit=root.hitTest(point)
      let row:[String:Any]=["open":open,"width":window.frame.width,"height":window.frame.height,"toolbarVisible":window.toolbar?.isVisible ?? false,"headerHitView":hit.map{String(describing:type(of:$0))} ?? "none","windowBackgroundDrag":window.isMovableByWindowBackground]
      var rows=(try? Data(contentsOf:url)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [[String:Any]]} ?? []
      rows.append(row)
      if let data=try? JSONSerialization.data(withJSONObject:Array(rows.suffix(40)),options:[.prettyPrinted,.sortedKeys]){try? data.write(to:url,options:.atomic)}
    }
  }
}
