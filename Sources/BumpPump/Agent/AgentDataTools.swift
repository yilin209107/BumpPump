import Foundation
import CoreFoundation

@MainActor struct AgentDataTools {
  let state:HomeState
  static var definitions:[AgentToolDefinition] {
    func schema(_ properties:[String:Any],_ required:[String])->[String:Any]{["type":"object","properties":properties,"required":required,"additionalProperties":false]}
    let str:[String:Any]=["type":"string"],number:[String:Any]=["type":"number"]
    let sections=["foods","activities","weights","foodLibrary","exerciseLibrary","energyGoal","profile","goals","measurements","plans","reminders","energy_days","sourceArchive","trash","removedLibrary"]
    return [
      .init(name:"read_app_data",description:"Read only this app's fitness data. Dates are yyyy-MM-dd. Search foodLibrary before recording a known food; query existing records before correcting or avoiding duplicates. sourceArchive returns table counts unless table is provided; it is historical evidence, not current state. Supports offset pagination.",parameters:schema(["section":["type":"string","enum":sections],"query":str,"start_date":str,"end_date":str,"table":str,"offset":["type":"integer","minimum":0],"limit":["type":"integer","minimum":1,"maximum":100]],["section"])),
      .init(name:"record_meal",description:"Atomically record foods actually eaten, not plans or hypothetical questions. food_id+quantity+unit uses an existing label and app-calculated nutrition. Otherwise supply name, amount, kcal (or kJ) and optional macros; estimates require uncertainty. Missing nutrients remain unknown. date yyyy-MM-dd; meal 早餐/午餐/晚餐/加餐; time HH:mm optional.",parameters:schema(["date":str,"meal":["type":"string","enum":DemoMealKind.allCases.map(\.rawValue)],"time":str,"foods":["type":"array","minItems":1,"maxItems":40,"items":schema(["food_id":str,"quantity":number,"unit":["type":"string","enum":["g","ml","份"]],"name":str,"amount":str,"kcal":number,"energy_unit":["type":"string","enum":["kcal","kJ"]],"protein_g":number,"carbs_g":number,"fat_g":number,"uncertainty":str],[ ])]],["date","meal","foods"])),
      .init(name:"record_activity",description:"Record an actual workout or cardio session. Strength sets preserve reps OR seconds, weight, basis (per_hand/per_side/total/machine_stack/bodyweight/assisted/resistance_rating/unknown), side(left/right/both), warmup, rir/rpe/restSeconds/notes. For paired sides give the same group number. Do not invent exercise durations, weight conventions, burned energy, or missing side values. categories 力量训练/有氧训练. date yyyy-MM-dd.",parameters:schema(["date":str,"time":str,"title":str,"category":["type":"string","enum":["力量训练","有氧训练"]],"muscles":["type":"array","items":str],"minutes":["type":"integer","minimum":0],"kcal":number,"notes":str,"sets":["type":"array","maxItems":200,"items":schema(["reps":["type":"integer","minimum":1],"seconds":number,"weight":number,"weightUnit":str,"basis":str,"side":str,"group":["type":"integer","minimum":1],"warmup":["type":"boolean"],"rir":number,"rpe":number,"restSeconds":number,"notes":str],[])]],["date","title","category"])),
      .init(name:"record_measurement",description:"Record a measured weight/height/body_fat/waist, never an assumed or target value. Weight supports kg/斤; height and waist cm; body_fat %. date yyyy-MM-dd.",parameters:schema(["date":str,"kind":["type":"string","enum":["weight","height","body_fat","waist"]],"value":number,"unit":str,"conditions":str],["date","kind","value","unit"])),
      .init(name:"change_app_data",description:"Create/update/remove/restore app-owned records or library items, update energyGoal, or manage profile/goals/measurements/plans/reminders/energy_days documents. Read first. Update/remove require id and expected_revision from latest read to avoid overwriting manual edits. remove is recoverable; sourceArchive is immutable evidence. No file paths, credentials, SQL, OS access. Canonical record formats come from read_app_data; data contains partial fields to merge on update. Library food fields are string values. energyGoal data is {value:number or null}. Set profile/plans only on user request, not guesses.",parameters:schema(["collection":["type":"string","enum":sections.filter{!["sourceArchive","trash","removedLibrary"].contains($0)}],"operation":["type":"string","enum":["create","update","remove","restore"]],"id":str,"expected_revision":["type":"integer"],"data":["type":"object","additionalProperties":true]],["collection","operation"]))
    ]
  }
  func execute(_ call:AgentToolCall,commandID:String) throws -> String {
    guard Self.definitions.contains(where:{$0.name==call.name}),call.arguments.utf8.count<=262144,let args=try JSONSerialization.jsonObject(with:Data(call.arguments.utf8)) as? [String:Any] else {throw AgentFailure("未知工具或无效参数，未执行。")}
    state.refreshLocalEntries()
    if call.name=="read_app_data" {return try read(args)}
    var savedIDs:[String]=[]
    try state.updateEntries(commandID:commandID,payload:call.name+call.arguments) { entries in
      switch call.name {
      case "record_meal":
        let date=try Self.date(args["date"]),clock=try Self.clock(args["time"])
        guard let kind=DemoMealKind(rawValue:args["meal"] as? String ?? ""),let foods=args["foods"] as? [[String:Any]],!foods.isEmpty,foods.count<=40 else {throw AgentFailure("请提供餐次与本次食物。")}
        for (i,item) in foods.enumerated() {
          let id="agent-\(commandID)-\(i)",nutrition:DemoNutrition,name:String,amount:String
          var product:HomePackagedFood?,quantity:Double?,unit:String?
          var origin=HomeRecordOrigin(source:"模型估算",recordID:commandID,note:item["uncertainty"] as? String ?? "")
          if let foodID=item["food_id"] as? String {
            guard let food=entries.foodLibrary?.first(where:{$0.id==foodID}) else {throw AgentFailure("食品标签不存在，请先查询食品库。")}
            let q=try Self.number(item["quantity"],"实际份量",min:0.001,max:100000),u=item["unit"] as? String ?? ""
            nutrition=try food.nutrition(quantity:q,unit:u);name=food.name;amount=HomeFormat.number(q,digits:1)+" "+u
            product=food;quantity=q;unit=u;origin = .init(source:food.source,recordID:food.id,note:"助理按现有标签与实际份量记录")
          } else {
            name=try Self.text(item["name"],"食物名称");amount=try Self.text(item["amount"],"份量")
            guard !origin.note.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw AgentFailure("估算食物需要说明份量假设和估算依据。")}
            var missing=Set<String>()
            @MainActor func macro(_ key:String) throws -> Double {guard let value=item[key],!(value is NSNull) else {missing.insert(key);return 0};return try Self.number(value,key,min:0,max:5000)}
            let p=try macro("protein_g"),c=try macro("carbs_g"),f=try macro("fat_g")
            let energy=try Self.number(item["kcal"],"热量",min:0,max:80000)/(item["energy_unit"] as? String == "kJ" ? 4.184:1)
            nutrition = .init(protein:p,carbs:c,fat:f,recordedEnergy:energy,missing:missing)
          }
          guard !entries.foods.contains(where:{$0.id==id}) else {continue}
          entries.foods.append(.init(id:id,date:date,kind:kind,time:clock,name:name,amount:amount,nutrition:nutrition,origin:origin,mealID:"agent-meal-"+commandID,foodID:product?.id,quantity:quantity,quantityUnit:unit,labelSnapshot:product));savedIDs.append(id)
        }
      case "record_activity":
        var data=args;data["id"]="agent-"+commandID;data["date"]=try Self.date(args["date"]).timeIntervalSinceReferenceDate;data["time"]=try Self.clock(args["time"])
        data["minutes"]=data["minutes"] ?? 0;data["muscles"]=data["muscles"] ?? [];data["notes"]=data["notes"] ?? ""
        if let raw=data["sets"] as? [[String:Any]] {data["sets"]=raw.enumerated().map {i,item in var item=item;item["id"]="agent-\(commandID)-set-\(i)";item["weightUnit"]=item["weightUnit"] ?? "kg";item["basis"]=item["basis"] ?? "unknown";item["warmup"]=item["warmup"] ?? false
          if let group=item["group"] as? Int,let side=item["side"] as? String,["left","right"].contains(side) {item["pairID"]="agent-\(commandID)-group-\(group)"};return item}}
        data["origin"]=["source":"用户描述 · 助理整理","recordID":commandID,"note":"保留用户描述的组数、负重口径与侧别"]
        let record:HomeAddedActivity=try Self.decode(data);try Self.validate(record);entries.activities.append(record);savedIDs=[record.id]
      case "record_measurement":
        let date=try Self.date(args["date"]),kind=args["kind"] as? String ?? "",unit=args["unit"] as? String ?? "",value=try Self.number(args["value"],"测量值",min:0.01,max:2000),id="agent-"+commandID
        let conditions=args["conditions"] as? String ?? ""
        if kind=="weight" {
          guard ["kg","斤"].contains(unit) else {throw AgentFailure("体重单位应为 kg 或斤。")}
          let jin=value*(unit=="kg" ? 2:1);guard jin<=2000 else {throw AgentFailure("体重数值超出有效范围。")}
          entries.weights.append(.init(id:id,date:date,jin:jin,conditions:conditions,order:(entries.weights.compactMap(\.order).max() ?? -1)+1,origin:.init(source:"用户测量",recordID:commandID,note:conditions)))
        } else {
          guard ["height","waist","body_fat"].contains(kind),unit==(kind=="body_fat" ? "%":"cm"),kind != "body_fat" || value<=100 else {throw AgentFailure("测量类型或单位不匹配。")}
          var docs=entries.documents ?? [:];if docs["measurements"]==nil{docs["measurements"]=entries.sourceArchive?["body_measurements"] ?? []};docs["measurements",default:[]].append(["id":id,"date":HomeFormat.date(date,pattern:"yyyy-MM-dd"),"kind":kind,"value":String(value),"unit":unit,"conditions":conditions]);entries.documents=docs
        };savedIDs=[id]
      case "change_app_data":savedIDs=try change(args,entries:&entries,commandID:commandID)
      default:throw AgentFailure("未知操作。")
      }
    }
    NotificationCenter.default.post(name:.agentRecordsChanged,object:nil)
    return try JSONSerialization.agentString(["ok":true,"committed":true,"revision":state.entries.revision ?? 0,"record_ids":savedIDs,"message":"本机记录已保存，图表已刷新。再次查询可核对结果。"])
  }
  private func read(_ args:[String:Any]) throws -> String {
    let section=args["section"] as? String ?? "",entries=state.entries
    let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(entries)) as! [String:Any]
    if section=="energyGoal" {return try JSONSerialization.agentString(["revision":entries.revision ?? 0,"value":entries.energyGoal as Any? ?? NSNull()])}
    var values:[[String:Any]]
    if section=="trash" {
      values=try (entries.trash ?? []).map {record in
        let encoded:Data
        switch record{case .food(let r):encoded=try JSONEncoder().encode(r);case .activity(let r):encoded=try JSONEncoder().encode(r);case .weight(let r):encoded=try JSONEncoder().encode(r)}
        return ["collection":record.kind == .food ? "foods":record.kind == .activity ? "activities":"weights","id":record.storageID,"record":try JSONSerialization.jsonObject(with:encoded)]
      }
    } else if section=="removedLibrary" {
      values=try (entries.removedLibrary ?? [:]).flatMap{collection,rows in try rows.map {bytes -> [String:Any] in let record=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] ?? [:];return ["collection":collection,"id":record["id"] ?? "","record":record]}}
    } else if section=="sourceArchive" {
      guard let table=args["table"] as? String else {return try JSONSerialization.agentString(["revision":entries.revision ?? 0,"tables":(entries.sourceArchive ?? [:]).mapValues(\.count)])}
      values=(entries.sourceArchive?[table] ?? []).map{$0 as [String:Any]}
    } else if ["foods","activities","weights","foodLibrary","exerciseLibrary"].contains(section) {
      // Optional libraries are omitted by Codable before their first item exists.
      // They are valid empty collections, not unknown database partitions.
      values=encoded[section] as? [[String:Any]] ?? []
    }
    else if ["profile","goals","measurements","plans","reminders","energy_days"].contains(section) {
      values=(entries.documents?[section] ?? []).map{$0 as [String:Any]}
      if values.isEmpty {values=(entries.sourceArchive?[section=="measurements" ? "body_measurements":section] ?? []).map{$0 as [String:Any]}}
    } else {throw AgentFailure("此数据分区不存在。")}
    let query=args["query"] as? String ?? "",start=args["start_date"] as? String,end=args["end_date"] as? String
    values=try values.filter { item in
      if !query.isEmpty,!(try JSONSerialization.agentString(item)).localizedCaseInsensitiveContains(query){return false}
      let day=(item["date"] as? Double).map{HomeFormat.date(Date(timeIntervalSinceReferenceDate:$0),pattern:"yyyy-MM-dd")} ?? (item["date"] as? String)
      if let day,day.count>=10{if let start,String(day.prefix(10))<start{return false};if let end,String(day.prefix(10))>end{return false}}
      return true
    }.map{item in var item=item;if let stamp=item["date"] as? Double{item["date"]=HomeFormat.date(Date(timeIntervalSinceReferenceDate:stamp),pattern:"yyyy-MM-dd")};return item}
    let offset=max(0,args["offset"] as? Int ?? 0),limit=min(100,max(1,args["limit"] as? Int ?? 20))
    var page=Array(values.dropFirst(offset).prefix(limit))
    while page.count>1,(try JSONSerialization.data(withJSONObject:page)).count>48000{page.removeLast()}
    return try JSONSerialization.agentString(["revision":entries.revision ?? 0,"section":section,"total":values.count,"rows":page,"next_offset":offset+page.count < values.count ? offset+page.count as Any : NSNull()])
  }
  private func change(_ args:[String:Any],entries:inout HomeDemoEntries,commandID:String) throws -> [String] {
    let collection=args["collection"] as? String ?? "",operation=args["operation"] as? String ?? "",id=args["id"] as? String ?? "agent-"+commandID
    guard ["create","update","remove","restore"].contains(operation) else {throw AgentFailure("无效操作。")}
    if operation != "create" {
      guard let expected=args["expected_revision"] as? Int,expected==(entries.revision ?? 0) else {throw AgentFailure("数据在你读取后已经变化。请重新查询，核对最新记录后再修改。")}
    }
    let data=args["data"] as? [String:Any] ?? [:]
    if collection=="energyGoal" {
      if operation=="create",entries.energyGoal != nil{throw AgentFailure("目标已存在，请先读取最新版本并使用update修改。")}
      if operation=="remove" || data["value"] is NSNull {entries.energyGoal=nil}
      else {entries.energyGoal=try Self.number(data["value"],"热量目标",min:1,max:20000)};return ["energyGoal"]
    }
    if ["profile","goals","measurements","plans","reminders","energy_days"].contains(collection) {
      var docs=entries.documents ?? [:],rows=docs[collection] ?? []
      if docs[collection]==nil{rows=entries.sourceArchive?[collection=="measurements" ? "body_measurements":collection] ?? []}
      if operation=="create",rows.contains(where:{$0["id"]==id}) {throw AgentFailure("相同标识的资料已存在，请读取最新版本后更新。")}
      if operation=="remove" {guard let i=rows.firstIndex(where:{$0["id"]==id}) else {throw AgentFailure("记录不存在。")};docs["removed_"+collection,default:[]].append(rows.remove(at:i))}
      else if operation=="restore" {guard let i=docs["removed_"+collection]?.firstIndex(where:{$0["id"]==id}),let row=docs["removed_"+collection]?.remove(at:i) else {throw AgentFailure("没有这条已移除记录。")};rows.append(row)}
      else {
        var row=operation=="update" ? rows.first(where:{$0["id"]==id}) ?? [:] : [:]
        if operation=="update",row.isEmpty {throw AgentFailure("记录不存在。")}
        for (key,value) in data {if let text=value as? String {row[key]=text}else{row[key]=try JSONSerialization.agentString(value)}}
        row["id"]=id;if let i=rows.firstIndex(where:{$0["id"]==id}){rows[i]=row}else{rows.append(row)}
      }
      docs[collection]=rows;entries.documents=docs;return[id]
    }
    func mutate<T:Codable & Identifiable>(_ records:inout [T],validate:(T)throws->Void) throws where T.ID==String {
      var removed=entries.removedLibrary ?? [:]
      if operation=="remove" {
        guard let i=records.firstIndex(where:{$0.id==id}) else {throw AgentFailure("记录不存在。")};let item=records.remove(at:i)
        var trash=entries.trash ?? []
        if let food=item as? HomeAddedFood{trash.append(.food(food))}else if let activity=item as? HomeAddedActivity{trash.append(.activity(activity))}else if let weight=item as? HomeAddedWeight{trash.append(.weight(weight))}else{removed[collection,default:[]].append(try JSONEncoder().encode(item))}
        entries.trash=trash
      }
      else if operation=="restore" {
        guard !records.contains(where:{$0.id==id}) else {throw AgentFailure("这条记录已存在。")}
        let kind=collection=="foods" ? HomeEntryKind.food:collection=="activities" ? .activity:.weight
        if ["foods","activities","weights"].contains(collection),let i=entries.trash?.firstIndex(where:{$0.storageID==id && $0.kind==kind}),let saved=entries.trash?.remove(at:i) {
          let value:Any;switch saved{case .food(let r):value=r;case .activity(let r):value=r;case .weight(let r):value=r}
          guard let item=value as? T else{throw AgentFailure("恢复记录类型不匹配。")};records.append(item)
        } else {
          guard let i=removed[collection]?.firstIndex(where:{(try? JSONDecoder().decode(T.self,from:$0).id)==id}),let bytes=removed[collection]?.remove(at:i) else {throw AgentFailure("没有这条已移除记录。")};records.append(try JSONDecoder().decode(T.self,from:bytes))
        }
      }
      else {
        var merged=data
        if operation=="update" {guard let previous=records.first(where:{$0.id==id}) else {throw AgentFailure("记录不存在。")};let old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(previous)) as! [String:Any];merged=Self.merge(old,data)}
        else if records.contains(where:{$0.id==id}){throw AgentFailure("相同标识的记录已经存在。")}
        merged["id"]=id
        if collection=="foods",data["quantity"] != nil || data["quantityUnit"] != nil || data["foodID"] != nil {
          guard let foodID=merged["foodID"] as? String else{throw AgentFailure("这条食物没有可换算的标签，请同时更新实际份量及营养估算。")}
          let food:HomePackagedFood
          if let snapshot=merged["labelSnapshot"] as? [String:Any],snapshot["id"] as? String==foodID{food=try Self.decode(snapshot)}else if let found=entries.foodLibrary?.first(where:{$0.id==foodID}){food=found}else{throw AgentFailure("食品标签不存在。")}
          let quantity=try Self.number(merged["quantity"],"实际份量",min:0.001,max:100000),unit=merged["quantityUnit"] as? String ?? ""
          merged["nutrition"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(food.nutrition(quantity:quantity,unit:unit)))
          merged["labelSnapshot"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(food));merged["amount"]=HomeFormat.number(quantity,digits:1)+" "+unit;merged["name"]=food.name
        }
        if collection=="foods",let changes=data["nutrition"] as? [String:Any],changes["missing"]==nil,var nutrition=merged["nutrition"] as? [String:Any]{
          var missing=Set(nutrition["missing"] as? [String] ?? [])
          for (key,field) in ["protein":"protein_g","carbs":"carbs_g","fat":"fat_g","recordedEnergy":"kcal"] where changes[key] != nil {
            if changes[key] is NSNull{missing.insert(field);nutrition[key]=0}else{missing.remove(field)}
          }
          nutrition["missing"]=missing.sorted();merged["nutrition"]=nutrition
        }
        if collection=="activities",let sets=merged["sets"] as? [[String:Any]]{merged["sets"]=sets.enumerated().map{i,set in var set=set;set["id"]=set["id"] ?? "agent-\(commandID)-set-\(i)";set["weightUnit"]=set["weightUnit"] ?? "kg";set["basis"]=set["basis"] ?? "unknown";set["warmup"]=set["warmup"] ?? false;return set}}
        if let date=merged["date"] as? String {merged["date"]=try Self.date(date).timeIntervalSinceReferenceDate}
        let record:T=try Self.decode(merged);try validate(record)
        if let i=records.firstIndex(where:{$0.id==id}){records[i]=record}else{records.append(record)}
      }
      entries.removedLibrary=removed
    }
    // Copy arrays before mutation to keep ownership exclusive across metadata updates.
    switch collection {
    case "foods":var rows=entries.foods;try mutate(&rows,validate:Self.validate);entries.foods=rows
    case "activities":var rows=entries.activities;try mutate(&rows,validate:Self.validate);entries.activities=rows
    case "weights":var rows=entries.weights;try mutate(&rows){r in _=try Self.number(r.jin,"体重",min:0.01,max:2000);_=try Self.date(HomeFormat.date(r.date,pattern:"yyyy-MM-dd"))};entries.weights=rows
    case "foodLibrary":var rows=entries.foodLibrary ?? [];try mutate(&rows){food in _=try Self.text(food.fields["name"],"食品名称");guard ["100g","100ml","serving"].contains(food.fields["basis"] ?? "") else {throw AgentFailure("食品标签须明确每100g、每100ml或每份。")};for key in ["kcal","protein_g","carbs_g","fat_g"] {if let value=food.fields[key]{_=try Self.number(Double(value),key,min:0,max:10000)}}};entries.foodLibrary=rows
    case "exerciseLibrary":var rows=entries.exerciseLibrary ?? [];try mutate(&rows){r in _=try Self.text(r.name,"动作名称");guard HomeExercise.bases.contains(r.basis) else {throw AgentFailure("负重口径无效。")}};entries.exerciseLibrary=rows
    default:throw AgentFailure("不允许修改这个数据区域。")
    };return[id]
  }
  nonisolated private static func merge(_ old:[String:Any],_ changes:[String:Any])->[String:Any] {
    old.merging(changes){previous,new in if let old=previous as? [String:Any],let changes=new as? [String:Any]{return merge(old,changes)};return new}
  }
  private static func decode<T:Decodable>(_ data:[String:Any]) throws -> T {do{return try JSONDecoder().decode(T.self,from:JSONSerialization.data(withJSONObject:data))}catch{throw AgentFailure("记录字段不完整或格式不匹配，请查询现有格式后再试。")}}
  private static func text(_ value:Any?,_ name:String) throws -> String {guard let s=value as? String,!s.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,s.count<=2000 else {throw AgentFailure("请提供有效的"+name+"。")};return s}
  private static func number(_ value:Any?,_ name:String,min:Double,max:Double) throws -> Double {guard let value,!(value is NSNull),let n=(value as? NSNumber)?.doubleValue,n.isFinite,n>=min,n<=max,CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() else {throw AgentFailure(name+"不是有效数值。")};return n}
  private static func date(_ value:Any?) throws -> Date {
    guard let value=value as? String,value.count==10 else {throw AgentFailure("日期应为 yyyy-MM-dd。")}
    let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone = .current;f.dateFormat="yyyy-MM-dd";f.isLenient=false
    guard let date=f.date(from:value),f.string(from:date)==value,date<=Calendar.current.startOfDay(for:Date()),value>="1900-01-01" else {throw AgentFailure("请提供今天或过去的有效日期。")};return date
  }
  private static func clock(_ value:Any?) throws -> String {guard let value=value as? String,!value.isEmpty else{return ""};let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="HH:mm";f.isLenient=false;guard let d=f.date(from:value),f.string(from:d)==value else{throw AgentFailure("时间应为 HH:mm。")};return value}
  private static func validate(_ r:HomeAddedFood) throws { _=try text(r.name,"食物名称");_=try text(r.amount,"份量");_=try date(HomeFormat.date(r.date,pattern:"yyyy-MM-dd"));for n in [r.nutrition.energy,r.nutrition.protein,r.nutrition.carbs,r.nutrition.fat]{_=try number(n,"营养",min:0,max:20000)} }
  private static func validate(_ r:HomeAddedActivity) throws {
    _=try text(r.title,"运动名称");_=try date(HomeFormat.date(r.date,pattern:"yyyy-MM-dd"));guard ["力量训练","有氧训练"].contains(r.category),(0...1440).contains(r.minutes),r.category != "有氧训练" || r.minutes>0 else{throw AgentFailure("运动类别或时长无效。")}
    if let kcal=r.kcal{_=try number(kcal,"消耗",min:0,max:20000)}
    guard (r.sets?.count ?? 0)<=200 else{throw AgentFailure("本次训练组数过多。")}
    for s in r.sets ?? [] {guard HomeExercise.bases.contains(s.basis),s.side==nil || ["left","right","both"].contains(s.side!),s.weightUnit=="kg",(s.reps != nil) != (s.seconds != nil) else {throw AgentFailure("每组需明确次数或秒数、负重口径和侧别。")};if let reps=s.reps{_=try number(reps,"次数",min:1,max:100000)};if let seconds=s.seconds{_=try number(seconds,"秒数",min:0.01,max:86400)};if let w=s.weight{_=try number(w,"重量",min:0,max:2000)};if let rir=s.rir{_=try number(rir,"RIR",min:0,max:20)};if let rpe=s.rpe{_=try number(rpe,"RPE",min:0,max:10)}}
  }
}
extension Notification.Name {static let agentRecordsChanged=Notification.Name("BumpPump.agentRecordsChanged")}
