import Foundation
import AppKit
import CSQLite

@MainActor @main enum AgentChecks {
  static func main() async throws {
    var count=0
    func check(_ condition:@autoclosure() throws -> Bool,_ message:String){count += 1;do{if try !condition(){fatalError(message)}}catch{fatalError(message+" error: "+error.localizedDescription)}}
    func json(_ value:Any)throws->String{try JSONSerialization.agentString(value)}
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("FitnessAgentChecks-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let label=HomePackagedFood(id:"food-fixture",fields:["name":"测试标签","basis":"100g","kcal":"110","protein_g":"10","carbs_g":"9","fat_g":"1","source":"label_text"])
    var legacy=HomeDemoEntries();legacy.foodLibrary=[label];legacy.sourceArchive=["profile":[["height_cm":"180"]]]
    let original=try JSONEncoder().encode(legacy);try original.write(to:directory.appendingPathComponent("entries.json"))
    let foreign=directory.appendingPathComponent("foreign.sqlite")
    var foreignDB:OpaquePointer?;sqlite3_open(foreign.path,&foreignDB);sqlite3_exec(foreignDB,"CREATE TABLE unrelated (value TEXT)",nil,nil,nil);sqlite3_close(foreignDB)
    let foreignBefore=try Data(contentsOf:foreign)
    do{_=try AppRecordDatabase(url:foreign).read();check(false,"Foreign database opened for writing")}catch{check(try Data(contentsOf:foreign)==foreignBefore,"Foreign database must remain byte-identical")}
    let store=HomeDemoEntryStore(url:directory.appendingPathComponent("fitness.sqlite"))
    let state=HomeState(preload:true,entryStore:store)
    check(state.entries.foodLibrary==[label] && state.entries.sourceArchive==legacy.sourceArchive,"Migration must preserve labels and raw archive")
    check(try Data(contentsOf:directory.appendingPathComponent("entries.json"))==original,"Migration must not alter original JSON")
    let tools=AgentDataTools(state:state),day=HomeFormat.date(Date(),pattern:"yyyy-MM-dd")
    let call=AgentToolCall(id:"meal-1",name:"record_meal",arguments:try json(["date":day,"meal":"早餐","foods":[["food_id":"food-fixture","quantity":150,"unit":"g"]]]))
    let first=try tools.execute(call,commandID:"request-1")
    check(first.contains("\"committed\":true") && state.entries.foods.count==1 && state.entries.foods[0].nutrition.energy==165,"Tool must calculate from label and commit")
    let rev=state.entries.revision
    _=try tools.execute(call,commandID:"request-1")
    check(state.entries.foods.count==1 && state.entries.revision==rev,"Tool replay must not duplicate or increase revision")
    var altered=call;altered.arguments=try json(["date":day,"meal":"早餐","foods":[["food_id":"food-fixture","quantity":200,"unit":"g"]]])
    do{_=try tools.execute(altered,commandID:"request-1");check(false,"Different payload reused command id")}catch{check(true,"Rejected changed replay")}
    let bad=AgentToolCall(id:"bad",name:"record_meal",arguments:try json(["date":day,"meal":"早餐","foods":[["food_id":"food-fixture","quantity":100,"unit":"g"],["food_id":"invented-id","quantity":1,"unit":"g"]]]))
    do{_=try tools.execute(bad,commandID:"bad-request");check(false,"Invalid meal saved")}catch{check(state.entries.foods.count==1,"A whole meal must rollback atomically")}
    let id=state.entries.foods[0].id
    let correction=AgentToolCall(id:"edit",name:"change_app_data",arguments:try json(["collection":"foods","operation":"update","id":id,"expected_revision":rev ?? 0,"data":["name":"已更正"]]))
    _=try tools.execute(correction,commandID:"edit-request");check(state.entries.foods[0].name=="已更正","Explicit correction must update identity")
    do{_=try tools.execute(correction,commandID:"stale-request");check(false,"Stale revision overwritten")}catch{check(true,"Stale writes rejected")}
    let undo=try AppRecordDatabase(url:store.url).undoLatest();check(undo.foods[0].name==label.name,"Undo must restore previous record")
    state.refreshLocalEntries()
    let remove=AgentToolCall(id:"remove",name:"change_app_data",arguments:try json(["collection":"foods","operation":"remove","id":id,"expected_revision":state.entries.revision ?? 0]))
    _=try tools.execute(remove,commandID:"remove-request");check(state.entries.foods.isEmpty && state.entries.trash?.count==1,"Remove must appear in the same UI trash")
    let restore=AgentToolCall(id:"restore",name:"change_app_data",arguments:try json(["collection":"foods","operation":"restore","id":id,"expected_revision":state.entries.revision ?? 0]))
    _=try tools.execute(restore,commandID:"restore-request");check(state.entries.foods.count==1,"Remove must be recoverable")
    let quantityChange=AgentToolCall(id:"quantity",name:"change_app_data",arguments:try json(["collection":"foods","operation":"update","id":id,"expected_revision":state.entries.revision ?? 0,"data":["quantity":200]]))
    _=try tools.execute(quantityChange,commandID:"quantity-request")
    check(abs(state.entries.foods[0].nutrition.energy-220)<0.00001 && state.entries.foods[0].quantity==200,"Quantity correction must recalculate nutrition from its saved label")
    let document=AgentToolCall(id:"profile",name:"change_app_data",arguments:try json(["collection":"plans","operation":"create","id":"plan-one","data":["title":"测试计划"]]))
    _=try tools.execute(document,commandID:"plan-create")
    do{_=try tools.execute(document,commandID:"plan-duplicate");check(false,"Create overwrote an existing document")}catch{check(state.entries.documents?["plans"]?.count==1,"Create must not bypass revision checks")}
    let readonly=AgentToolCall(id:"shell",name:"run_shell",arguments:"{}")
    do{_=try tools.execute(readonly,commandID:"shell-request");check(false,"Arbitrary tool executed")}catch{check(true,"Unknown tools rejected")}
    let forbidden=AgentToolCall(id:"archive",name:"change_app_data",arguments:try json(["collection":"sourceArchive","operation":"create","data":["path":"/etc/passwd"]]))
    do{_=try tools.execute(forbidden,commandID:"archive-request");check(false,"Raw archive changed")}catch{check(true,"External/raw scope rejected")}
    let custom=AgentToolCall(id:"custom",name:"record_meal",arguments:try json(["date":day,"meal":"加餐","foods":[["name":"手填","amount":"1份","kcal":418.4,"energy_unit":"kJ","uncertainty":"用户标签，份量一份"]]]))
    _=try tools.execute(custom,commandID:"custom-request");check(abs(state.entries.foods.last!.nutrition.energy-100)<0.0001 && !state.entries.foods.last!.nutrition.isKnown("protein_g"),"kJ conversion and missing nutrients")
    let workout=AgentToolCall(id:"workout",name:"record_activity",arguments:try json(["date":day,"title":"哑铃弯举","category":"力量训练","muscles":["大臂"],"sets":[["reps":12,"weight":5,"basis":"per_side","side":"left","group":1],["reps":10,"weight":4.5,"basis":"per_side","side":"right","group":1]]]))
    _=try tools.execute(workout,commandID:"workout-request");check(state.entries.activities.last?.sets?.logicalGroupCount==1 && state.entries.activities.last?.minutes==0,"Paired sets preserve logical group and unknown duration")
    let injection=AgentToolCall(id:"inject",name:"record_measurement",arguments:try json(["date":"$(rm -rf /)","kind":"weight","value":70,"unit":"kg"]))
    do{_=try tools.execute(injection,commandID:"injected");check(false,"Invalid date accepted")}catch{check(true,"Untrusted parameters treated as data")}
    let before=try store.read().foods.count
    let another=HomeState(preload:true,entryStore:store)
    try another.addWeight(.init(date:Date(),jin:140,conditions:"测试"))
    try state.addFood(.init(date:Date(),kind:.lunch,time:"12:00",name:"新食物",amount:"1份",nutrition:.init(protein:1,carbs:1,fat:1)))
    check(try store.read().weights.count==1 && store.read().foods.count==before+1,"Manual and agent windows must not lose each other's changes")
    for format in [AgentSSEDecoder.Format.chat,.responses,.claude,.gemini] {
      var decoder=AgentSSEDecoder(format:format)
      switch format {
      case .chat:
        _=try decoder.consume(#"{"choices":[{"delta":{"content":"你好","tool_calls":[{"index":0,"id":"call-1","function":{"name":"read_app_data","arguments":"{\"section\":"}}]}}]}"#)
        check(decoder.turn.text=="你好","Text should appear before response completes")
        _=try decoder.consume(try json(["choices":[["delta":["tool_calls":[["index":0,"function":["arguments":"\"foods\"}"]]]],"finish_reason":"tool_calls"]]]))
      case .responses:
        _=try decoder.consume(try json(["type":"response.output_text.delta","delta":"你好"]))
        _=try decoder.consume(try json(["type":"response.completed","response":["output":[["type":"function_call","call_id":"call-1","name":"read_app_data","arguments":"{\"section\":\"foods\"}"]]]]))
      case .claude:
        _=try decoder.consume(try json(["type":"content_block_start","index":0,"content_block":["type":"text","text":""]]))
        _=try decoder.consume(try json(["type":"content_block_delta","index":0,"delta":["type":"text_delta","text":"你好"]]))
        _=try decoder.consume(try json(["type":"content_block_start","index":1,"content_block":["type":"tool_use","id":"call-1","name":"read_app_data","input":[:]]]))
        _=try decoder.consume(try json(["type":"content_block_delta","index":1,"delta":["type":"input_json_delta","partial_json":"{\"section\":\"foods\"}"]]))
        _=try decoder.consume(try json(["type":"message_stop"]))
      case .gemini:
        _=try decoder.consume(try json(["candidates":[["content":["parts":[["text":"你好"],["functionCall":["name":"read_app_data","args":["section":"foods"]],"thoughtSignature":"fixture-signature"]]],"finishReason":"STOP"]]]))
      }
      let turn=try decoder.finish();check(turn.text=="你好" && turn.calls.first?.name=="read_app_data","All provider formats normalize text and calls")
      if format == .gemini{check(String(data:turn.native!,encoding:.utf8)!.contains("fixture-signature"),"Native tool signatures must round-trip")}
    }
    var reasoningDecoder=AgentSSEDecoder(format:.chat)
    _=try reasoningDecoder.consume(try json(["choices":[["delta":["reasoning_content":"fixture reasoning","content":"答复"],"finish_reason":"stop"]]]))
    let reasoningTurn=try reasoningDecoder.finish()
    let reasoningMessage=AgentMessage(role:"assistant",text:reasoningTurn.text,native:reasoningTurn.native,nativeProvider:"deepseek")
    let (preservedRequest,_)=try AgentHTTPTransport.request(configuration:.init(providerID:"deepseek",key:"fixture",model:"fixture"),system:"fixture",messages:[reasoningMessage],tools:[])
    let preservedBody=try JSONSerialization.jsonObject(with:preservedRequest.httpBody!) as! [String:Any]
    check((preservedBody["messages"] as? [[String:Any]])?.last?["reasoning_content"] as? String=="fixture reasoning","Provider-required reasoning context must round-trip without entering visible reply")
    var broken=AgentSSEDecoder(format:.chat);_=try broken.consume("{\"choices\":[{\"delta\":{\"content\":\"半句\"}}]}")
    do{_=try broken.finish();check(false,"Truncated stream accepted")}catch{check(true,"Truncated response must never execute")}
    for provider in APIProvider.all {
      let c=APIConnectionConfiguration(providerID:provider.id,key:"fixture-not-real",model:provider.models.first ?? "fixture-model",endpoint:provider.id=="custom" ? "https://fixture.invalid/v1":"")
      let (request,_)=try AgentHTTPTransport.request(configuration:c,system:"fixture",messages:[.init(role:"user",text:"你好")],tools:AgentDataTools.definitions)
      check(request.value(forHTTPHeaderField:"Accept")=="text/event-stream","Every provider must request streaming")
      check(!String(data:request.httpBody!,encoding:.utf8)!.contains("fixture-not-real"),"API key must not enter model content")
      check(!request.url!.absoluteString.contains("fixture-not-real"),"Key must stay out of URL")
    }
    let file=directory.appendingPathComponent("meal.txt");try "食物标签 418.4kJ".write(to:file,atomically:true,encoding:.utf8)
    check(try AgentAttachments.load(file).text=="食物标签 418.4kJ","User-selected text must be copied as data")
    let binary=directory.appendingPathComponent("program.command");try "echo no".write(to:binary,atomically:true,encoding:.utf8)
    do{_=try AgentAttachments.load(binary);check(false,"Executable accepted")}catch{check(true,"Executable attachments rejected")}
    let transportConfig=APIConnectionConfiguration(providerID:"deepseek",key:"fixture-not-real",model:"fixture")
    let sessionConfig=URLSessionConfiguration.ephemeral;sessionConfig.protocolClasses=[FixtureSSEProtocol.self]
    let httpTransport=AgentHTTPTransport(session:URLSession(configuration:sessionConfig))
    FixtureSSEProtocol.mode = .success
    var received=""
    let streamed=try await httpTransport.stream(configuration:transportConfig,system:"fixture",messages:[.init(role:"user",text:"你好")],tools:[]) {fragment in received += fragment;FixtureSSEProtocol.deltaSeenBeforeEnd = !FixtureSSEProtocol.ended}
    check(received=="你好" && streamed.text=="你好","HTTP stream must decode split UTF8 bytes incrementally")
    check(FixtureSSEProtocol.deltaSeenBeforeEnd,"Streaming must deliver text before the connection completes")
    FixtureSSEProtocol.mode = .truncated
    do{_=try await httpTransport.stream(configuration:transportConfig,system:"fixture",messages:[],tools:[],delta:{_ in});check(false,"HTTP truncated response accepted")}catch{check(true,"Real HTTP reader rejects a missing terminal event")}
    FixtureSSEProtocol.mode = .rejected
    let requestCount=FixtureSSEProtocol.requests
    do{_=try await httpTransport.stream(configuration:transportConfig,system:"fixture",messages:[],tools:[],delta:{_ in});check(false,"HTTP error accepted")}catch{check(FixtureSSEProtocol.requests==requestCount+1,"Rejected requests must not automatically replay")}
    let suite="AgentChecks."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
    defer{defaults.removePersistentDomain(forName:suite)}
    let setup=SetupState(defaults:defaults),agent=FitnessAgentState()
    agent.draft="测试查询";agent.send(home:state,setup:setup,transport:FixtureAgentTransport(),configuration:.init(providerID:"deepseek",key:"fixture-not-real",model:"fixture"))
    for _ in 0..<200 where agent.busy{try await Task.sleep(for:.milliseconds(10))}
    check(!agent.busy && agent.error==nil && agent.messages.contains{$0.role=="tool"} && agent.messages.last?.text=="查询完成。","Agent loop must stream, execute local tool, feed result and finish")
    let writing=FitnessAgentState(),beforeAgentWrite=state.entries.foods.count
    writing.draft="记录测试标签100g";writing.send(home:state,setup:setup,transport:WritingAgentFixture(day:day),configuration:transportConfig)
    for _ in 0..<200 where writing.busy{try await Task.sleep(for:.milliseconds(10))}
    check(writing.error==nil && state.entries.foods.count==beforeAgentWrite+1 && writing.messages.last?.text=="已记录。","Full agent write loop must commit once and return the actual receipt")
    let cancelled=FitnessAgentState(),beforeCancel=try store.read().foods.count
    cancelled.draft="隔离取消测试";cancelled.send(home:state,setup:setup,transport:CancelledAgentFixture(day:day),configuration:transportConfig)
    try await Task.sleep(for:.milliseconds(20));cancelled.cancel()
    for _ in 0..<200 where cancelled.busy{try await Task.sleep(for:.milliseconds(10))}
    check(try !cancelled.busy && store.read().foods.count==beforeCancel,"Cancelling an incomplete tool response must not commit")
    let persisted=FitnessAgentState(directory:directory.appendingPathComponent("history"))
    persisted.conversations=[.init(messages:[.init(role:"user",text:"记录"),.init(role:"assistant",text:"",calls:[.init(id:"saved-call",name:"record_meal",arguments:"{}"),.init(id:"pending-call",name:"record_meal",arguments:"{}")],interrupted:true),.init(role:"tool",text:"{\"ok\":true,\"committed\":true}",callID:"saved-call",toolName:"record_meal")])];persisted.selectedID=persisted.conversations[0].id
    persisted.draft="继续核对";persisted.send(home:state,setup:setup,transport:InterruptedContextFixture(),configuration:transportConfig)
    for _ in 0..<200 where persisted.busy{try await Task.sleep(for:.milliseconds(10))}
    check(persisted.error==nil && persisted.messages.last?.text=="回执保留。","Interrupted groups must retain completed receipts without dangling tool messages")
    let report:[String:Any]=["ok":true,"assertions":count,"realAPIRequests":0,"realRecordsRead":false,"scope":"isolated SQLite migration, command receipts, rollback, conflicts, undo, provider SSE, attachments and full agent loop"]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"work/agent-checks/report.json"))
    print("Agent checks passed: \(count)")
  }
}
private struct FixtureAgentTransport:AgentTransport {
  func stream(configuration:APIConnectionConfiguration,system:String,messages:[AgentMessage],tools:[AgentToolDefinition],delta:@escaping @MainActor(String)->Void) async throws -> AgentTurn {
    if messages.last?.role=="tool"{await delta("查询");try await Task.sleep(for:.milliseconds(10));await delta("完成。");return .init(text:"查询完成。")}
    return .init(calls:[.init(id:"fixture-call",name:"read_app_data",arguments:"{\"section\":\"foods\"}")])
  }
}

private final class FixtureSSEProtocol:URLProtocol,@unchecked Sendable {
  enum Mode {case success,truncated,rejected}
  static var mode=Mode.success
  static var requests=0
  static var ended=false
  static var deltaSeenBeforeEnd=false
  private var stopped=false
  override class func canInit(with request:URLRequest)->Bool{true}
  override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
  override func startLoading(){
    Self.requests += 1;Self.ended=false
    let mode=Self.mode
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:mode == .rejected ? 401:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
    if mode == .rejected{Self.ended=true;client?.urlProtocolDidFinishLoading(self);return}
    let first=Data("data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\n".utf8)
    // Split a multibyte Chinese code point across transport chunks.
    let split=first.firstIndex(of:0xe4).map{$0+1} ?? first.count/2
    client?.urlProtocol(self,didLoad:first.prefix(split))
    DispatchQueue.global().asyncAfter(deadline:.now()+0.02){[self] in
      guard !stopped else{return};client?.urlProtocol(self,didLoad:first.dropFirst(split))
      DispatchQueue.global().asyncAfter(deadline:.now()+0.06){[self] in
        guard !stopped else{return}
        if mode == .success{client?.urlProtocol(self,didLoad:Data("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8))}
        Self.ended=true;client?.urlProtocolDidFinishLoading(self)
      }
    }
  }
  override func stopLoading(){stopped=true}
}
private struct InterruptedContextFixture:AgentTransport {
  func stream(configuration:APIConnectionConfiguration,system:String,messages:[AgentMessage],tools:[AgentToolDefinition],delta:@escaping @MainActor(String)->Void)async throws->AgentTurn {
    guard messages.contains(where:{$0.text.contains("committed")}),!messages.contains(where:{$0.role=="tool" || !$0.calls.isEmpty}) else{throw AgentFailure("Interrupted receipts were lost or dangling")}
    return .init(text:"回执保留。")
  }
}

private struct WritingAgentFixture:AgentTransport {
  let day:String
  func stream(configuration:APIConnectionConfiguration,system:String,messages:[AgentMessage],tools:[AgentToolDefinition],delta:@escaping @MainActor(String)->Void)async throws->AgentTurn {
    if messages.last?.role=="tool"{guard messages.last!.text.contains("committed") else{throw AgentFailure("Missing commit receipt")};await delta("已记录。");return .init(text:"已记录。")}
    return .init(calls:[.init(id:"write-fixture",name:"record_meal",arguments:try JSONSerialization.agentString(["date":day,"meal":"早餐","foods":[["food_id":"food-fixture","quantity":100,"unit":"g"]]]))])
  }
}
private struct CancelledAgentFixture:AgentTransport {
  let day:String
  func stream(configuration:APIConnectionConfiguration,system:String,messages:[AgentMessage],tools:[AgentToolDefinition],delta:@escaping @MainActor(String)->Void)async throws->AgentTurn {
    try await Task.sleep(for:.seconds(1));return .init(calls:[.init(id:"never-execute",name:"record_meal",arguments:"{}")])
  }
}
