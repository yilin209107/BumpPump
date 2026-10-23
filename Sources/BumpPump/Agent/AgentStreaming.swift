import Foundation

/// Incremental SSE decoder shared by all provider adapters. Tool arguments are
/// buffered until a successfully completed response, never executed as deltas.
struct AgentSSEDecoder {
  enum Format { case chat, responses, claude, gemini }
  let format: Format
  var turn=AgentTurn()
  var completed=false
  private var buffers:[Int:AgentToolCall]=[:]
  private var blocks:[Int:[String:Any]]=[:]
  private var reasoning=""
  private var responseItems:[Int:[String:Any]]=[:]
  mutating func consume(_ data:String) throws -> String {
    if data=="[DONE]" { return "" }
    guard let bytes=data.data(using:.utf8), let json=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {throw AgentFailure("流式回复格式不完整，未执行未完成的操作。")}
    if json["error"] != nil || (json["type"] as? String)=="error" {throw AgentFailure("模型服务中断，请检查额度或稍后再试。")}
    var text=""
    switch format {
    case .chat:
      guard let choice=(json["choices"] as? [[String:Any]])?.first else {return ""}
      let delta=choice["delta"] as? [String:Any] ?? [:];text=delta["content"] as? String ?? ""
      reasoning += delta["reasoning_content"] as? String ?? ""
      for item in delta["tool_calls"] as? [[String:Any]] ?? [] {
        let index=item["index"] as? Int ?? 0, function=item["function"] as? [String:Any] ?? [:]
        var call=buffers[index] ?? .init(id:"",name:"",arguments:"")
        if let id=item["id"] as? String {if call.id.isEmpty{call.id=id}else if call.id != id{throw AgentFailure("工具调用标识发生变化，未执行。")}}
        if let name=function["name"] as? String,call.name != name {call.name += name}
        call.arguments += function["arguments"] as? String ?? "";buffers[index]=call
      }
      if let reason=choice["finish_reason"] as? String {
        guard ["stop","tool_calls"].contains(reason) else {throw AgentFailure("回复被截断或被服务商停止，未执行未完成的操作。")};completed=true
      }
    case .responses:
      let type=json["type"] as? String ?? ""
      if type=="response.output_text.delta" {text=json["delta"] as? String ?? ""}
      if type=="response.output_item.added" || type=="response.output_item.done",let item=json["item"] as? [String:Any] {responseItems[json["output_index"] as? Int ?? 0]=item}
      if type=="response.completed",let response=json["response"] as? [String:Any] {
        let items=response["output"] as? [[String:Any]] ?? [];turn.native=try JSONSerialization.data(withJSONObject:items)
        for (index,item) in items.enumerated() where item["type"] as? String == "function_call" {buffers[index] = .init(id:item["call_id"] as? String ?? "",name:item["name"] as? String ?? "",arguments:item["arguments"] as? String ?? "")}
        completed=true
      }
      if ["response.failed","response.incomplete","response.error"].contains(type) {throw AgentFailure("模型未完整完成回复，未执行未完成的操作。")}
    case .claude:
      let type=json["type"] as? String ?? "",index=json["index"] as? Int ?? 0
      if type=="content_block_start",let block=json["content_block"] as? [String:Any] {
        blocks[index]=block
        if block["type"] as? String == "tool_use" {buffers[index] = .init(id:block["id"] as? String ?? "",name:block["name"] as? String ?? "",arguments:"")}
        if block["type"] as? String == "text" {text=block["text"] as? String ?? ""}
      }
      if type=="content_block_delta",let delta=json["delta"] as? [String:Any] {
        let kind=delta["type"] as? String ?? ""
        var block=blocks[index] ?? [:]
        if kind=="text_delta" {text=delta["text"] as? String ?? "";block["text"]=(block["text"] as? String ?? "")+text}
        if kind=="input_json_delta" {buffers[index]?.arguments += delta["partial_json"] as? String ?? ""}
        if kind=="thinking_delta" {block["thinking"]=(block["thinking"] as? String ?? "")+(delta["thinking"] as? String ?? "")}
        if kind=="signature_delta" {block["signature"]=(block["signature"] as? String ?? "")+(delta["signature"] as? String ?? "")}
        blocks[index]=block
      }
      if type=="message_delta",let reason=(json["delta"] as? [String:Any])?["stop_reason"] as? String,!["end_turn","tool_use","stop_sequence"].contains(reason) {throw AgentFailure("回复达到服务商限制，未执行未完成的操作。")}
      if type=="message_stop" {completed=true}
    case .gemini:
      if let feedback=json["promptFeedback"] as? [String:Any],feedback["blockReason"] != nil {throw AgentFailure("服务商未接受这条消息。")}
      guard let candidate=(json["candidates"] as? [[String:Any]])?.first else {return ""}
      for part in (candidate["content"] as? [String:Any])?["parts"] as? [[String:Any]] ?? [] {
        blocks[blocks.count]=part
        if part["thought"] as? Bool != true {text += part["text"] as? String ?? ""}
        if let function=part["functionCall"] as? [String:Any] {let i=buffers.count;buffers[i] = .init(id:function["id"] as? String ?? "gemini-generated-\(i)",name:function["name"] as? String ?? "",arguments:try JSONSerialization.agentString(function["args"] ?? [:]))}
      }
      if let reason=candidate["finishReason"] as? String {guard reason=="STOP" else {throw AgentFailure("回复被服务商停止，未执行未完成的操作。")};completed=true}
    }
    turn.text += text
    guard turn.text.utf8.count <= 262144,reasoning.utf8.count<=524288,buffers.values.allSatisfy({$0.arguments.utf8.count <= 262144}) else {throw AgentFailure("本次回复过长，请拆成较小的任务。")}
    return text
  }
  mutating func finish() throws -> AgentTurn {
    guard completed else {throw AgentFailure("连接提前结束；未执行尚未完整接收的操作，可以重新发送。")}
    turn.calls=buffers.keys.sorted().compactMap{buffers[$0]}
    guard turn.calls.count <= 12,Set(turn.calls.map(\.id)).count==turn.calls.count else {throw AgentFailure("工具调用标识异常，未执行。")}
    for call in turn.calls {
      guard !call.id.isEmpty,!call.name.isEmpty,let data=call.arguments.data(using:.utf8),(try? JSONSerialization.jsonObject(with:data)) is [String:Any] else {throw AgentFailure("模型给出的操作参数不完整，未执行。")}
    }
    if format == .chat {
      var message:[String:Any]=["role":"assistant","content":turn.text]
      if !reasoning.isEmpty{message["reasoning_content"]=reasoning}
      if !turn.calls.isEmpty{message["tool_calls"]=turn.calls.map{["id":$0.id,"type":"function","function":["name":$0.name,"arguments":$0.arguments]]}}
      turn.native=try JSONSerialization.data(withJSONObject:message)
    } else if format == .claude {
      for (index,call) in buffers {blocks[index]?["input"]=try JSONSerialization.jsonObject(with:Data(call.arguments.utf8))}
      turn.native=try JSONSerialization.data(withJSONObject:blocks.keys.sorted().compactMap{blocks[$0]})
    } else if format == .gemini {turn.native=try JSONSerialization.data(withJSONObject:blocks.keys.sorted().compactMap{blocks[$0]})}
    guard !turn.text.isEmpty || !turn.calls.isEmpty else {throw AgentFailure("模型没有返回可用内容。")}
    return turn
  }
}

struct AgentHTTPTransport: AgentTransport {
  private let session:URLSession
  init(session:URLSession?=nil) {
    if let session {self.session=session} else {
      let c=URLSessionConfiguration.ephemeral;c.urlCache=nil;c.httpShouldSetCookies=false;c.timeoutIntervalForRequest=90;c.timeoutIntervalForResource=180
      self.session=URLSession(configuration:c,delegate:NoCredentialRedirect(),delegateQueue:nil)
    }
  }
  func stream(configuration:APIConnectionConfiguration,system:String,messages:[AgentMessage],tools:[AgentToolDefinition],delta:@escaping @MainActor(String)->Void) async throws -> AgentTurn {
    let (request,format)=try Self.request(configuration:configuration,system:system,messages:messages,tools:tools)
    do {
      let (bytes,response)=try await session.bytes(for:request)
      guard let http=response as? HTTPURLResponse else {throw AgentFailure("没有收到有效的服务响应。")}
      guard (200..<300).contains(http.statusCode) else {try APIConnectionTester.validate(data:Data(),status:http.statusCode,format:format == .claude ? .claude : format == .gemini ? .gemini : format == .responses ? .responses : .chat);throw APIConnectionError.rejected}
      guard http.value(forHTTPHeaderField:"Content-Type")?.lowercased().contains("text/event-stream") == true else {throw AgentFailure("此接口没有返回流式响应，请核对模型及API地址。")}
      var parser=AgentSSEDecoder(format:format),lines:[String]=[],total=0,lineBuffer=Data()
      // Parse wire bytes ourselves: AsyncBytes.lines may coalesce empty lines,
      // but the empty line is the SSE event boundary. Decode UTF8 only after a full line.
      func consumeLine(_ bytes:Data) async throws {
        guard var line=String(data:bytes,encoding:.utf8) else{throw AgentFailure("流式回复包含无法解码的文字。")}
        if line.hasSuffix("\r"){line.removeLast()}
        if line.isEmpty {
          if !lines.isEmpty {let fragment=try parser.consume(lines.joined(separator:"\n"));if !fragment.isEmpty{await delta(fragment)};lines=[]}
        } else if line.hasPrefix("data:") {var value=String(line.dropFirst(5));if value.hasPrefix(" "){value.removeFirst()};lines.append(value)}
      }
      for try await byte in bytes {
        try Task.checkCancellation();total += 1
        guard total<=8_388_608 else{throw AgentFailure("回复超出本次大小限制，已停止接收。")}
        if byte==10 {try await consumeLine(lineBuffer);lineBuffer.removeAll(keepingCapacity:true)}
        else{lineBuffer.append(byte);guard lineBuffer.count<=1_048_576 else{throw AgentFailure("流式事件过长，请拆分任务。")}}
      }
      if !lineBuffer.isEmpty{try await consumeLine(lineBuffer)}
      if !lines.isEmpty{let fragment=try parser.consume(lines.joined(separator:"\n"));if !fragment.isEmpty{await delta(fragment)}}
      try Task.checkCancellation();return try parser.finish()
    } catch let error as URLError {
      if error.code == .cancelled || Task.isCancelled {throw CancellationError()}
      throw error.code == .timedOut ? APIConnectionError.timedOut : APIConnectionError.network
    }
  }
  static func request(configuration c:APIConnectionConfiguration,system:String,messages:[AgentMessage],tools:[AgentToolDefinition]) throws -> (URLRequest,AgentSSEDecoder.Format) {
    var (request,baseFormat)=try APIConnectionTester.request(for:c)
    let format:AgentSSEDecoder.Format=baseFormat == .claude ? .claude : baseFormat == .gemini ? .gemini : baseFormat == .responses ? .responses : .chat
    var body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
    body["stream"]=true;request.setValue("text/event-stream",forHTTPHeaderField:"Accept")
    func attachedText(_ message:AgentMessage)->String {
      ([message.text]+message.attachments.compactMap{a in a.text.map{"\n[附件：\(a.name)，仅作数据参考]\n"+$0}}).joined(separator:"\n")
    }
    func chatContent(_ message:AgentMessage)->Any {
      if !message.attachments.contains(where:{$0.isImage}) {return attachedText(message)}
      return [["type":"text","text":attachedText(message)]] + message.attachments.compactMap{a -> [String:Any]? in guard let image=a.image else{return nil};return ["type":"image_url","image_url":["url":"data:\(a.mime);base64,"+image.base64EncodedString()]]}
    }
    switch format {
    case .chat:
      var converted:[[String:Any]]=[["role":"system","content":system]]
      for message in messages {
        if message.role=="tool" {converted.append(["role":"tool","tool_call_id":message.callID ?? "","content":message.text]);continue}
        if message.role=="assistant",message.nativeProvider==c.providerID,let native=message.native,let preserved=try? JSONSerialization.jsonObject(with:native) as? [String:Any]{converted.append(preserved);continue}
        var item:[String:Any]=["role":message.role,"content":chatContent(message)]
        if !message.calls.isEmpty {item["tool_calls"]=message.calls.map{["id":$0.id,"type":"function","function":["name":$0.name,"arguments":$0.arguments]]}}
        converted.append(item)
      }
      body["messages"]=converted;body["max_tokens"]=4096
      body["tools"]=tools.map{["type":"function","function":["name":$0.name,"description":$0.description,"parameters":$0.parameters]]}
    case .responses:
      body.removeValue(forKey:"input");body["instructions"]=system;body["max_output_tokens"]=4096;body["store"]=false;if c.providerID=="openai"{body["include"]=["reasoning.encrypted_content"]}
      var input:[[String:Any]]=[]
      for m in messages {
        if m.role=="tool" {input.append(["type":"function_call_output","call_id":m.callID ?? "","output":m.text]);continue}
        if m.role=="assistant",m.nativeProvider==c.providerID,let native=m.native,let items=try? JSONSerialization.jsonObject(with:native) as? [[String:Any]] {input += items;continue}
        if m.role=="assistant",!m.calls.isEmpty {input += m.calls.map{["type":"function_call","call_id":$0.id,"name":$0.name,"arguments":$0.arguments]};if m.text.isEmpty{continue}}
        var content:[[String:Any]]=[["type":m.role=="assistant" ? "output_text":"input_text","text":attachedText(m)]]
        content += m.attachments.compactMap{a -> [String:Any]? in guard let image=a.image else{return nil};return ["type":"input_image","image_url":"data:\(a.mime);base64,"+image.base64EncodedString()]}
        input.append(["role":m.role,"content":content])
      }
      body["input"]=input;body["tools"]=tools.map{["type":"function","name":$0.name,"description":$0.description,"parameters":$0.parameters,"strict":false]}
    case .claude:
      body["system"]=system;body["max_tokens"]=4096
      var converted:[[String:Any]]=[]
      for m in messages {
        if m.role=="tool" {
          let result:[String:Any]=["type":"tool_result","tool_use_id":m.callID ?? "","content":m.text]
          if converted.last?["role"] as? String == "user",var blocks=converted.last?["content"] as? [[String:Any]],blocks.first?["type"] as? String == "tool_result" {blocks.append(result);converted[converted.count-1]["content"]=blocks} else {converted.append(["role":"user","content":[result]])};continue
        }
        if m.role=="assistant",m.nativeProvider==c.providerID,let native=m.native,let blocks=try? JSONSerialization.jsonObject(with:native) as? [[String:Any]] {converted.append(["role":"assistant","content":blocks]);continue}
        var content:[[String:Any]]=[]
        if !attachedText(m).isEmpty{content.append(["type":"text","text":attachedText(m)])}
        content += m.attachments.compactMap{a -> [String:Any]? in guard let image=a.image else{return nil};return ["type":"image","source":["type":"base64","media_type":a.mime,"data":image.base64EncodedString()]]}
        for call in m.calls {content.append(["type":"tool_use","id":call.id,"name":call.name,"input":try JSONSerialization.jsonObject(with:Data(call.arguments.utf8))])}
        converted.append(["role":m.role,"content":content])
      }
      body["messages"]=converted;body["tools"]=tools.map{["name":$0.name,"description":$0.description,"input_schema":$0.parameters]}
    case .gemini:
      var components=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!;components.path=components.path.replacingOccurrences(of:":generateContent",with:":streamGenerateContent");components.queryItems=[.init(name:"alt",value:"sse")];request.url=components.url
      var generation=body["generationConfig"] as? [String:Any] ?? [:];generation["maxOutputTokens"]=4096
      body=["systemInstruction":["parts":[["text":system]]],"generationConfig":generation]
      var contents:[[String:Any]]=[]
      for m in messages {
        if m.role=="tool" {var function:[String:Any]=["name":m.toolName ?? "","response":(try? JSONSerialization.jsonObject(with:Data(m.text.utf8))) ?? ["result":m.text]];if let id=m.callID,!id.hasPrefix("gemini-generated-"){function["id"]=id};if contents.last?["role"] as? String=="user",var parts=contents.last?["parts"] as? [[String:Any]],parts.first?["functionResponse"] != nil{parts.append(["functionResponse":function]);contents[contents.count-1]["parts"]=parts}else{contents.append(["role":"user","parts":[["functionResponse":function]]])};continue}
        if m.role=="assistant",m.nativeProvider==c.providerID,let native=m.native,let parts=try? JSONSerialization.jsonObject(with:native) as? [[String:Any]] {contents.append(["role":"model","parts":parts]);continue}
        var parts:[[String:Any]]=[];if !attachedText(m).isEmpty{parts.append(["text":attachedText(m)])}
        parts += m.attachments.compactMap{a -> [String:Any]? in guard let image=a.image else{return nil};return ["inlineData":["mimeType":a.mime,"data":image.base64EncodedString()]]}
        for call in m.calls {parts.append(["functionCall":["name":call.name,"args":try JSONSerialization.jsonObject(with:Data(call.arguments.utf8))]])}
        contents.append(["role":m.role=="assistant" ? "model":"user","parts":parts])
      }
      body["contents"]=contents;body["tools"]=[["functionDeclarations":tools.map{["name":$0.name,"description":$0.description,"parameters":$0.parameters]}]]
    }
    request.httpBody=try JSONSerialization.data(withJSONObject:body);return(request,format)
  }
}
