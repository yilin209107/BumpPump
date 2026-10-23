import SwiftUI
import AppKit

/// This editor owns only text input. Return follows normal macOS text editing;
/// Shift-Return submits only after any active input-method composition finishes.
struct AssistantMessageEditor:NSViewRepresentable {
  @Binding var text:String
  @Binding var measuredHeight:CGFloat
  var editable:Bool
  var submit:()->Void

  func makeCoordinator()->Coordinator {Coordinator(self)}
  func makeNSView(context:Context)->AssistantEditorScrollView {
    let scroll=AssistantEditorScrollView()
    let editor=AssistantInputTextView(frame:.zero)
    editor.isRichText=false
    editor.importsGraphics=false
    editor.allowsUndo=true
    editor.isAutomaticQuoteSubstitutionEnabled=false
    editor.isAutomaticDashSubstitutionEnabled=false
    editor.isAutomaticTextReplacementEnabled=false
    editor.font = .systemFont(ofSize:14)
    editor.drawsBackground=false
    editor.textContainerInset = .zero
    editor.textContainer?.lineFragmentPadding=0
    editor.isVerticallyResizable=true
    editor.isHorizontallyResizable=false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView=true
    editor.textContainer?.heightTracksTextView=false
    editor.textContainer?.containerSize=NSSize(width:1,height:CGFloat.greatestFiniteMagnitude)
    editor.setAccessibilityLabel("给助理的消息")
    editor.setAccessibilityHelp("按 Enter 换行，按 Shift + Enter 发送。")
    editor.delegate=context.coordinator
    editor.submit={ [weak coordinator=context.coordinator] in coordinator?.submit() }
    scroll.documentView=editor
    scroll.drawsBackground=false
    scroll.borderType = .noBorder
    scroll.hasHorizontalScroller=false
    scroll.hasVerticalScroller=false
    scroll.autohidesScrollers=true
    scroll.scrollerStyle = .overlay
    scroll.layoutChanged={ [weak coordinator=context.coordinator,weak scroll] in
      if let scroll {coordinator?.measure(scroll)}
    }
    return scroll
  }
  func updateNSView(_ scroll:AssistantEditorScrollView,context:Context) {
    context.coordinator.owner=self
    guard let editor=scroll.documentView as? AssistantInputTextView else{return}
    editor.isEditable=editable
    editor.isSelectable=true
    editor.textColor=editable ? .labelColor:.secondaryLabelColor
    editor.insertionPointColor = .labelColor
    if editor.string != text && !editor.hasMarkedText() {
      let selection=editor.selectedRange()
      editor.string=text
      let location=min(selection.location,(text as NSString).length)
      editor.setSelectedRange(NSRange(location:location,length:0))
    }
    context.coordinator.measure(scroll)
  }

  final class Coordinator:NSObject,NSTextViewDelegate {
    var owner:AssistantMessageEditor
    init(_ owner:AssistantMessageEditor){self.owner=owner}
    func submit(){guard owner.editable else{return};owner.submit()}
    func textDidChange(_ notification:Notification) {
      guard let editor=notification.object as? AssistantInputTextView else{return}
      owner.text=editor.string
      if let scroll=editor.enclosingScrollView as? AssistantEditorScrollView {measure(scroll)}
    }
    func measure(_ scroll:AssistantEditorScrollView) {
      guard let editor=scroll.documentView as? AssistantInputTextView,
            let container=editor.textContainer,let manager=editor.layoutManager else{return}
      let width=scroll.contentSize.width
      guard width > 1 else{return}
      container.containerSize=NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
      if abs(editor.frame.width-width)>0.5 {editor.setFrameSize(NSSize(width:width,height:editor.frame.height))}
      manager.ensureLayout(for:container)
      let line=manager.defaultLineHeight(for:editor.font ?? .systemFont(ofSize:14))
      let fullHeight=ceil(max(line,manager.usedRect(for:container).maxY,manager.extraLineFragmentRect.maxY))
      let height=min(ceil(line*6),fullHeight)
      let documentHeight=max(fullHeight,scroll.contentSize.height)
      if abs(editor.frame.height-documentHeight)>0.5 {editor.setFrameSize(NSSize(width:width,height:documentHeight))}
      scroll.hasVerticalScroller=fullHeight > height+0.5
      if abs(owner.measuredHeight-height)>0.5 {
        DispatchQueue.main.async { [weak self] in
          guard let self,abs(self.owner.measuredHeight-height)>0.5 else{return}
          self.owner.measuredHeight=height
        }
      }
    }
  }
}

final class AssistantEditorScrollView:NSScrollView {
  var layoutChanged:(()->Void)?
  private var previousWidth:CGFloat=0
  override func layout() {
    super.layout()
    if abs(contentSize.width-previousWidth)>0.5 {previousWidth=contentSize.width;layoutChanged?()}
  }
}

final class AssistantInputTextView:NSTextView {
  var submit:(()->Void)?
  override func keyDown(with event:NSEvent) {
    // Do not intercept candidate confirmation for Chinese, Japanese, or other IMEs.
    if Self.sendsMessage(event,hasMarkedText:hasMarkedText()) {
      guard isEditable,!event.isARepeat else{return}
      submit?()
      return
    }
    super.keyDown(with:event)
  }
  static func sendsMessage(_ event:NSEvent,hasMarkedText:Bool)->Bool {
    guard !hasMarkedText,event.keyCode == 36 || event.keyCode == 76 else{return false}
    let modifiers=event.modifierFlags.intersection([.shift,.command,.control,.option])
    return modifiers == .shift
  }
}
