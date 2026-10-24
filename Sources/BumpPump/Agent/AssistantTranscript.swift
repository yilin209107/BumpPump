import SwiftUI

/// Presentation only: original tool receipts remain intact for API context and auditing.
enum AssistantTranscript {
  struct Row:Identifiable {
    let id:String
    var message:AgentMessage?
    var readCount:Int?
  }
  static func rows(_ messages:[AgentMessage])->[Row] {
    var result:[Row]=[],summaryIndex:Int?,seen=Set<String>()
    for message in messages {
      if message.role=="user" {summaryIndex=nil;seen=[]}
      if message.role=="tool",message.toolName=="read_app_data",
         let json=(try? JSONSerialization.jsonObject(with:Data(message.text.utf8))) as? [String:Any],
         json["ok"] as? Bool != false {
        if summaryIndex==nil {summaryIndex=result.count;result.append(.init(id:"reads-"+message.id,readCount:0))}
        let section=json["section"] as? String ?? "metadata"
        for row in json["rows"] as? [[String:Any]] ?? [] {
          let identity: String
          if let id=row["id"] as? String,!id.isEmpty {identity=id}
          else {identity=(try? JSONSerialization.data(withJSONObject:row,options:.sortedKeys)).map{$0.base64EncodedString()} ?? UUID().uuidString}
          seen.insert(section+"|"+identity)
        }
        // A scalar target is one actual record; table directories contain metadata only.
        if let value=json["value"],!(value is NSNull) {seen.insert("energyGoal")}
        if let summaryIndex {result[summaryIndex].readCount=seen.count}
      } else if message.role != "assistant" || !message.text.isEmpty {
        result.append(.init(id:message.id,message:message))
      }
    }
    return result
  }
}

struct AssistantReadReceipt:View {
  let count:Int
  @Environment(\.accessibilityReduceMotion) private var reduced
  @State private var shown=0
  var body:some View {
    HStack(spacing:7) {
      Image(systemName:"magnifyingglass")
      HStack(spacing:0) {
        Text("已查看本机 ")
        Text(shown,format:.number.grouping(.never)).monospacedDigit()
          .contentTransition(.numericText(value:Double(shown)))
        Text(" 条记录")
      }
    }.font(.system(size:11)).foregroundStyle(.secondary)
      .accessibilityElement(children:.ignore).accessibilityLabel("已查看本机\(count)条记录")
      .onAppear{update()}.onChange(of:count){_,_ in update()}
  }
  private func update(){withAnimation(reduced ? nil:.smooth(duration:0.65)){shown=count}}
}
