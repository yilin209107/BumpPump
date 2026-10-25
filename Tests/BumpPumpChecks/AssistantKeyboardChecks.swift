import AppKit
import SwiftUI

@main struct AssistantKeyboardChecks {
  @MainActor static func main() {
    _ = NSApplication.shared
    var count=0
    func check(_ condition:Bool,_ message:String) {precondition(condition,message);count += 1}
    func key(_ modifiers:NSEvent.ModifierFlags=[],code:UInt16=36,repeating:Bool=false)->NSEvent {
      NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:repeating,keyCode:code)!
    }
    check(!AssistantInputTextView.sendsMessage(key(),hasMarkedText:false),"Return must not send")
    check(AssistantInputTextView.sendsMessage(key(.shift),hasMarkedText:false),"Shift-Return must send")
    check(AssistantInputTextView.sendsMessage(key([.shift,.capsLock]),hasMarkedText:false),"Caps Lock must not change Shift-Return")
    check(AssistantInputTextView.sendsMessage(key(.shift,code:76),hasMarkedText:false),"Shift-keypad Enter must send")
    check(!AssistantInputTextView.sendsMessage(key([.shift,.command]),hasMarkedText:false),"Other command combinations must remain native")
    check(!AssistantInputTextView.sendsMessage(key(.shift),hasMarkedText:true),"IME composition must never trigger submit")

    let editor=AssistantInputTextView(frame:NSRect(x:0,y:0,width:240,height:100))
    editor.isRichText=false;editor.isEditable=true
    check(editor.showsPlaceholder,"An empty native editor should show its placeholder")
    var sends=0
    editor.submit={sends += 1}
    editor.string="第一行";editor.setSelectedRange(NSRange(location:(editor.string as NSString).length,length:0))
    editor.keyDown(with:key())
    check(editor.string=="第一行\n","Native Return must insert a newline")
    check(sends==0,"Native Return must not invoke submit")
    let draft=editor.string
    editor.keyDown(with:key(.shift))
    check(sends==1,"Shift-Return must invoke submit once")
    check(editor.string==draft,"Shift-Return must not insert a newline")
    editor.keyDown(with:key(.shift,repeating:true))
    check(sends==1,"Key repeat must not submit again")
    editor.isEditable=false
    editor.keyDown(with:key(.shift))
    check(sends==1,"A busy/disabled editor must not submit")
    editor.isEditable=true
    editor.setMarkedText("ni",selectedRange:NSRange(location:2,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
    check(editor.hasMarkedText(),"Native composition fixture must contain marked text")
    check(!editor.showsPlaceholder,"An IME composition must hide the placeholder before committing text")
    check(!AssistantInputTextView.sendsMessage(key(.shift),hasMarkedText:editor.hasMarkedText()),"An active native composition must preserve its confirmation key")
    print("Assistant keyboard checks: \(count) assertions passed")
  }
}
