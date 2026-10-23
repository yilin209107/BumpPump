import Foundation

@main enum HomeDataChecks {
  @MainActor static func main() async {
    var assertions = 0
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) { assertions += 1; if !condition { failures.append(message) } }
    let calendar = Calendar.current
    let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
    let coldStart = HomeState(anchor: anchor, usesExamples: true)
    coldStart.load()
    let deadline = Date().addingTimeInterval(3)
    while coldStart.isLoading && Date() < deadline { await Task.yield() }
    check(!coldStart.isLoading && coldStart.days.count == 90, "Cold launch must finish loading")
    let earlyActivation = HomeState(anchor: anchor, usesExamples: true)
    earlyActivation.refreshCalendar(now: calendar.date(byAdding: .day, value: 1, to: anchor)!)
    earlyActivation.load()
    check(!earlyActivation.isLoading && earlyActivation.days.count == 90, "Activation before the initial task must not leave the loading skeleton visible")
    let state = HomeState(anchor: anchor, preload: true, usesExamples: true)
    check(state.days.count == 90, "Expected ninety demo dates")
    check(state.days.last?.date == anchor, "Last demo date must be anchor")
    check(Set(state.days.map(\.id)).count == 90, "Day IDs must be unique")
    let meals = state.days.flatMap(\.meals)
    check(Set(meals.map(\.id)).count == meals.count, "Meal IDs must be unique")
    for day in state.days {
      let energy = day.meals.reduce(0) { $0 + $1.foods.reduce(0) { $0 + $1.nutrition.energy } }
      check(abs(day.nutrition.energy - energy) < 0.001, "Daily total must equal source foods")
      check(day.nutrition.energy > 0, "Demo day must contain nutrition")
      check(day.meals.contains { $0.kind == .snack }, "Demo day must include snack")
      check(day.activities.filter { $0.category == "力量训练" }.allSatisfy { $0.kcal == nil }, "Strength energy must not be fabricated")
    }
    state.range = 7
    check(state.history.count == 7, "Seven-day range must include both boundaries")
    check(state.history.last?.date == state.selectedDate, "Range must end at selected day")
    check(state.history.first?.date == calendar.date(byAdding: .day, value: -6, to: anchor), "Range first boundary incorrect")
    state.range = 30; check(state.history.count == 30, "Thirty-day range incorrect")
    state.range = 90; check(state.history.count == 90, "Ninety-day range incorrect")
    state.selectedDate = state.days.first!.date
    check(state.history.count == 1, "Early-date range must not fabricate prior records")
    state.selectedDate = anchor; state.range = 7
    let stackSum = state.energy.reduce(0) { $0 + $1.kcal }
    check(abs(stackSum-state.history.reduce(0) { $0 + $1.nutrition.energy }) < 0.001, "Stacked meal energy must equal day totals")
    check(state.energy.count == 28, "Snacks must aggregate to four meal kinds per day")
    check(state.weights.allSatisfy { point in state.history.contains { $0.date == point.date && $0.weightJin == point.jin } }, "Weight points must resolve to original measurements")
    state.query = "鸡胸"
    check(state.searchResults.contains { $0.title == "香煎鸡胸肉" && $0.destination == .meal(.lunch) }, "Food search incorrect")
    state.query = "肩"; check(state.searchResults.contains { $0.destination == .strength("肩") }, "Muscle search incorrect")
    state.query = "not-a-demo-item"; check(state.searchResults.isEmpty, "Unknown search must have no matches")
    state.select(.overview); check(state.query.isEmpty, "Selecting destination should clear search")
    check(HomeDestination.strengthNames == ["小臂", "大臂", "肩", "胸", "背", "腹", "大腿", "小腿"], "Requested muscles must be preserved")
    check(HomeDestination.cardioNames == ["篮球", "羽毛球", "跑步", "足球", "乒乓球", "其他"], "Requested sports must be preserved")
    let weight = state.weights.last!
    state.showWeight(weight)
    check(state.detail?.date == weight.date, "Weight detail date incorrect")
    check(state.detail?.rows.contains { $0.value == HomeFormat.number(weight.jin/2, digits: 2) + " kg" } == true, "Jin to kg conversion incorrect")
    let meal = state.day!.meals.first!
    state.showMeal(meal, date: anchor)
    check(state.detail?.rows.count == meal.foods.count + 2, "Meal detail must include every source food and nutrition totals")
    let size = CGSize(width: 1000, height: 700)
    var fluid = HomeFluidPhysics(), freeFluid = HomeFluidPhysics()
    let start = CGPoint(x: 0.25, y: 0.4), target = CGPoint(x: 0.8, y: 0.65)
    for _ in 0..<120 {
      fluid.advance(target: start, size: size, elapsed: 1.0/30)
      freeFluid.advance(target: start, size: size, elapsed: 1.0/30, interactions: false)
    }
    check(fluid.blobs.count == 5, "Expected five independently moving coloured bodies")
    check(fluid.contacts > 0, "Soft bodies must make contact")
    let deformation = zip(fluid.blobs, freeFluid.blobs).reduce(0.0) { total, pair in
      total + zip(pair.0.radial, pair.1.radial).reduce(0.0) { $0 + abs($1.0-$1.1) }
    }
    check(deformation > 0.5, "Contact must deform outlines, beyond ambient breathing")
    let before = fluid.blobs.map { $0.center.x }.reduce(0, +)/5
    fluid.advance(target: target, size: size, elapsed: 1.0/30)
    let following = fluid.blobs.map { $0.center.x }.reduce(0, +)/5
    check(following > before && following < 700, "Pointer following needs inertia, not teleportation")
    check(fluid.blobs.contains { $0.velocity.length > 1 }, "Pointer movement must produce velocity")
    for _ in 0..<180 { fluid.advance(target: target, size: size, elapsed: 1.0/30) }
    let center = fluid.blobs.map(\.center).reduce(HomeFluidVector(), +)*0.2
    check(hypot(center.x-800, center.y-455) < 45, "Group must settle around the pointer")
    for step in 0..<240 {
      fluid.advance(target: CGPoint(x: step%2 == 0 ? 0.05 : 0.95, y: step%3 == 0 ? 0.1 : 0.9), size: size, elapsed: step%7 == 0 ? 4 : 1.0/30)
      check(fluid.blobs.allSatisfy { blob in blob.center.x.isFinite && blob.center.y.isFinite && blob.radial.allSatisfy { $0.isFinite && $0 >= 0.55 && $0 <= 1.45 } }, "Soft-body solver became unstable")
      let outline = HomeFluidSurface.outline(fluid.blobs)
      let centroid = fluid.blobs.map(\.center).reduce(HomeFluidVector(), +)*0.2
      check(outline.count == 72 && outline.allSatisfy { $0.x.isFinite && $0.y.isFinite && hypot($0.x-centroid.x, $0.y-centroid.y) > 30 }, "Shared liquid surface must remain a single closed, non-collapsed radial envelope")
    }
    let contentBounds = CGRect(x: 228, y: 0, width: 772, height: 700)
    for wallTarget in [CGPoint(x: 0.228,y: 0.5), CGPoint(x: 1,y: 0.5), CGPoint(x: 0.6,y: 0), CGPoint(x: 0.6,y: 1)] {
      var confined = HomeFluidPhysics(), unconstrained = HomeFluidPhysics()
      for _ in 0..<180 {
        confined.advance(target: wallTarget, size: size, elapsed: 1.0/30, bounds: contentBounds)
        unconstrained.advance(target: wallTarget, size: size, elapsed: 1.0/30, bounds: contentBounds, walls: false)
      }
      check(confined.wallContacts > 0, "Each wall, including the sidebar, must apply contact forces")
      let shapeChange = zip(confined.blobs,unconstrained.blobs).reduce(0.0) { total,pair in total+zip(pair.0.radial,pair.1.radial).reduce(0.0) { $0+abs($1.0-$1.1) } }
      check(shapeChange > 0.8, "Wall contact must change radial geometry, not merely clip or relocate the glow")
      check(confined.blobs.flatMap(\.points).allSatisfy { $0.x >= contentBounds.minX-0.01 && $0.x <= contentBounds.maxX+0.01 && $0.y >= contentBounds.minY-0.01 && $0.y <= contentBounds.maxY+0.01 }, "Soft body nodes must not penetrate a wall")
      let contour = HomeFluidSurface.outline(confined.blobs,bounds: contentBounds)
      check(contour.allSatisfy { $0.x >= contentBounds.minX-0.01 && $0.x <= contentBounds.maxX+0.01 && $0.y >= contentBounds.minY-0.01 && $0.y <= contentBounds.maxY+0.01 }, "Shared surface must stay inside all four walls")
      check(confined.blobs.contains { $0.radial.min()! < 0.8 && $0.radial.max()! > 1.03 }, "Compression must flatten the contact side and bulge another side")
      let compressed = confined.blobs.flatMap(\.radial)
      for _ in 0..<180 { confined.advance(target: CGPoint(x: 0.6,y: 0.5), size: size, elapsed: 1.0/30, bounds: contentBounds) }
      check(confined.wallContacts == 0, "Moving away must release wall contact")
      let released = confined.blobs.flatMap(\.radial)
      check(zip(compressed,released).reduce(0.0) { $0+abs($1.0-$1.1) } > 0.8, "Body must recover after leaving the wall")
    }
    var changingBounds = HomeFluidPhysics()
    for step in 0..<240 {
      let currentSize = step < 120 ? size : CGSize(width: 760,height: 640)
      let sidebarWidth = step%60 < 30 ? 270.0 : 0.0
      let bounds = CGRect(x: sidebarWidth,y: 0,width: currentSize.width-sidebarWidth,height: currentSize.height)
      changingBounds.advance(target: CGPoint(x: step%2 == 0 ? 0 : 1,y: step%3 == 0 ? 0 : 1), size: currentSize, elapsed: step%13 == 0 ? 3 : 1.0/30, bounds: bounds)
      let contour = HomeFluidSurface.outline(changingBounds.blobs,bounds: bounds)
      check(contour.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x >= bounds.minX-0.01 && $0.x <= bounds.maxX+0.01 && $0.y >= bounds.minY-0.01 && $0.y <= bounds.maxY+0.01 }, "Corner impacts, sidebar toggles and window resizing must remain finite and contained")
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HomeEntries.Test." + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HomeDemoEntryStore(url: directory.appendingPathComponent("entries.json"))
    do {
      let editable = HomeState(anchor: anchor, preload: true, entryStore: store, usesExamples: true)
      let originalEnergy = editable.day!.nutrition.energy
      let food = HomeAddedFood(date: anchor, kind: .lunch, time: "13:00", name: "演示手填食品", amount: "1 份", nutrition: .init(protein: 10, carbs: 20, fat: 5))
      try editable.addFood(food); try editable.addFood(food)
      check(editable.entries.foods.count == 1, "Repeated submit must not duplicate added food")
      check(abs(editable.day!.nutrition.energy-originalEnergy-165) < 0.001, "Added nutrition must flow into daily totals")
      let beforeActivities = editable.day!.activities.count
      try editable.addActivity(.init(date: anchor, title: "羽毛球", category: "有氧训练", time: "20:00", minutes: 30, kcal: nil, muscles: [], notes: "演示输入"))
      check(editable.day!.activities.count == beforeActivities+1, "Added activity missing from selected day")
      check(editable.day!.activities.last?.kcal == nil, "Unknown energy must stay nil")
      check(editable.day!.activities.last?.energySource == "手动填写", "Manual activity must not be mislabeled as device estimation")
      let draft = HomeEntryDraft(kind: .weight, date: anchor, goal: nil)
      draft.weight = "60.5"; draft.unit = "kg"; draft.notes = "空腹"
      check(draft.submit(to: editable), "Weight form save failed")
      check(!draft.submit(to: editable), "Duplicate form submission must be rejected")
      check(editable.day!.weightJin == 121, "Weight form kg conversion incorrect")
      let weightPoint = editable.weights.first { $0.date == anchor }!
      editable.showWeight(weightPoint)
      check(editable.detail?.rows.contains { $0.value == "空腹" } == true, "Manual measurement conditions must be preserved")
      let invalid = HomeEntryDraft(kind: .food, date: anchor, goal: nil)
      check(!invalid.submit(to: editable) && invalid.error != nil, "Empty food form must show an inline error")
      let goalDraft = HomeEntryDraft(kind: .energy, date: anchor, goal: nil)
      goalDraft.goal = "2300"
      check(goalDraft.submit(to: editable), "Goal form failed")
      check(editable.energyGoal == 2300, "Goal not reflected by chart state")
      let restored = HomeState(anchor: anchor, preload: true, entryStore: store, usesExamples: true)
      check(restored.energyGoal == 2300 && restored.entries.foods.count == 1, "Records and goal must survive relaunch")
      check(restored.day!.weightJin == 121, "Weight must survive relaunch")
      check(abs(restored.day!.nutrition.energy-originalEnergy-165) < 0.001, "Restoring must not apply food twice")
      let saved = try Data(contentsOf: store.url)
      do { try restored.setEnergyGoal(-1); check(false, "Negative goal accepted") } catch { check(true, "Invalid goal rejected") }
      let unchanged = try Data(contentsOf: store.url)
      check(unchanged == saved, "Invalid input must not alter the saved file")
      try restored.setEnergyGoal(nil)
      check(HomeState(anchor: anchor, preload: true, entryStore: store, usesExamples: true).energyGoal == nil, "Removing goal should persist")
      let oldDate = calendar.date(from: DateComponents(year: 2025, month: 5, day: 6))!
      try restored.addWeight(.init(date: oldDate, jin: 120, conditions: "旧日期"))
      check(restored.selectedDate == oldDate && restored.weights.count == 1, "Direct historic date entry must show the new measurement")
      check(restored.day!.meals.isEmpty, "Historical weight must not fabricate meals")
      try Data("damaged".utf8).write(to: store.url)
      let blocked = HomeState(anchor: anchor, preload: true, entryStore: store, usesExamples: true)
      check(blocked.entryStorageError != nil, "Corrupt local records need a repair message")
      do { try blocked.setEnergyGoal(2200); check(false, "Damaged records were overwritten") } catch { check(true, "Damaged records preserved") }
      let damaged = try Data(contentsOf: store.url)
      check(damaged == Data("damaged".utf8), "Damaged record bytes must be preserved")
    } catch { check(false, "Uncaught entry-store error: " + error.localizedDescription) }
    let goalStepper = HomeEntryDraft(kind: .energy, date: anchor, goal: nil)
    check(goalStepper.goal == "2000", "Goal control should show the requested initial number without saving it")
    goalStepper.adjustGoal(by: 50)
    check(goalStepper.goal == "2050", "Plus must add exactly 50 kcal")
    goalStepper.adjustGoal(by: -50)
    check(goalStepper.goal == "2000", "Minus must subtract exactly 50 kcal")
    goalStepper.goal = "50"; goalStepper.adjustGoal(by: -50)
    check(goalStepper.goal == "50", "Goal stepper must not underflow")
    goalStepper.goal = "20000"; goalStepper.adjustGoal(by: 50)
    check(goalStepper.goal == "20000", "Goal stepper must not overflow")
    for kind in DemoMealKind.allCases {
      let mealState = HomeState(anchor: anchor, preload: true, usesExamples: true)
      mealState.recordMeal(kind)
      check(mealState.entry == .food && mealState.entryMeal == kind, "Meal plus must preserve its category")
    }
    let unknownLabel = HomePackagedFood(id: "fixture", fields: ["name": "标签测试", "basis": "100ml", "source": "reference"])
    check(unknownLabel.value("kcal", unit: "kcal") == "—", "Unknown label energy must not be inferred")
    check(unknownLabel.basis == "每 100 ml", "Food label basis must remain explicit")
    check(unknownLabel.source == "参考值", "Reference provenance must remain visible")
    let editsURL = directory.appendingPathComponent("edit-workspace.json")
    let editStore = HomeDemoEntryStore(url: editsURL)
    do {
      let a = HomeState(anchor: anchor, preload: true, entryStore: editStore, usesExamples: true)
      let b = HomeState(anchor: anchor, preload: true, entryStore: editStore, usesExamples: true)
      let input = HomeAddedFood(date: anchor, kind: .breakfast, time: "09:00", name: "手动测试餐", amount: "1 份", nutrition: .init(protein: 10, carbs: 20, fat: 5))
      try a.addFood(input)
      try b.setEnergyGoal(2100)
      check(try editStore.read().foods.count == 1, "Other window goal save must preserve records")
      a.refreshLocalEntries()
      let draft = HomeEntryDraft(record: .food(input), goal: a.energyGoal)
      draft.name = "改后的餐"; draft.protein = "20"
      check(draft.submit(to: a), "Editing food failed")
      check(a.entries.foods.count == 1 && a.entries.foods[0].name == "改后的餐", "Editing must replace, not duplicate")
      let after = a.day!.nutrition.energy
      let saved = a.localRecords.first { $0.storageID == input.id }!
      try a.moveToTrash(saved)
      check(a.entries.foods.isEmpty && a.removedRecords.count == 1, "Move to trash must keep recoverable data")
      check(abs(a.day!.nutrition.energy-after+165) < 0.001, "Removal must update chart aggregates")
      let relaunch = HomeState(anchor: anchor, preload: true, entryStore: editStore, usesExamples: true)
      check(relaunch.removedRecords.count == 1, "Trash must persist after relaunch")
      let staleEdit = HomeEntryDraft(record: saved, goal: nil)
      check(!staleEdit.submit(to: relaunch), "A stale editor must not resurrect removed data")
      try relaunch.restoreRecord(saved)
      check(relaunch.entries.foods.count == 1 && relaunch.removedRecords.isEmpty, "Restore must preserve the original ID exactly once")
      do { try relaunch.restoreRecord(saved); check(false, "Repeated restore should not duplicate") } catch { check(relaunch.entries.foods.count == 1, "Repeated restore altered active records") }
      let firstWeight = HomeAddedWeight(date: anchor, jin: 120, conditions: "第一次")
      let lastWeight = HomeAddedWeight(date: anchor, jin: 121, conditions: "第二次")
      try relaunch.addWeight(firstWeight); try relaunch.addWeight(lastWeight)
      let old = relaunch.localRecords.first { $0.storageID == firstWeight.id }!
      try relaunch.moveToTrash(old); try relaunch.restoreRecord(old)
      check(relaunch.day!.weightJin == 121, "Restoring older same-day weight must not make it newest")
      let weightEdit = HomeEntryDraft(record: .weight(relaunch.entries.weights.first { $0.id == lastWeight.id }!), goal: nil)
      weightEdit.weight = "122"
      check(weightEdit.submit(to: relaunch) && relaunch.day!.weightJin == 122, "Editing last weight must update trend")
      let activity = HomeAddedActivity(date: anchor, title: "跑步", category: "有氧训练", time: "19:00", minutes: 20, kcal: nil, muscles: [], notes: "")
      try relaunch.addActivity(activity)
      let activityEdit = HomeEntryDraft(record: .activity(activity), goal: nil)
      activityEdit.minutes = "35"; activityEdit.notes = "修改备注"
      check(activityEdit.submit(to: relaunch) && relaunch.entries.activities.last?.minutes == 35 && relaunch.entries.activities.last?.kcal == nil, "Activity edit must preserve unknown calories")
      let water = HomeAddedFood(date: anchor, kind: .snack, time: "16:00", name: "水", amount: "250 ml", nutrition: .init())
      try relaunch.addFood(water)
      check(relaunch.entries.foods.contains { $0.id == water.id }, "Zero-calorie records must be allowed")
      let oldDate = Calendar.current.date(byAdding: .day, value: -2, to: anchor)!
      relaunch.selectedDate = oldDate
      let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: anchor)!
      relaunch.refreshCalendar(now: nextDay)
      check(relaunch.anchor == nextDay && relaunch.selectedDate == oldDate, "Midnight refresh must preserve historical selection")
      relaunch.selectedDate = nextDay
      let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: nextDay)!
      relaunch.refreshCalendar(now: tomorrow)
      check(relaunch.selectedDate == tomorrow, "Today selection should follow the new day")
      relaunch.select(.cardio("足球")); relaunch.beginContextEntry()
      check(relaunch.entry == .activity, "Cardio context must open activity recording")
      relaunch.select(.strength("肩")); relaunch.beginContextEntry()
      check(relaunch.entry == .activity, "Strength context must open activity recording")
      relaunch.packagedFoods = [HomePackagedFood(id: "catalog-search", fields: ["name": "包装搜索食品", "brand": "搜索品牌", "basis": "100g"])]
      relaunch.query = "搜索品牌"
      let found = relaunch.searchResults.first { $0.catalogFoodID == "catalog-search" }
      check(found != nil, "Global search must find catalogue brands")
      if let found { relaunch.selectSearchResult(found) }
      check(relaunch.destination == .foods && relaunch.selectedPackagedFood?.id == "catalog-search" && relaunch.query.isEmpty, "Catalogue search must open the exact label")
      let backup = try HomeRecordBackup.encode(relaunch.entries)
      let decodedBackup = try JSONDecoder().decode(HomeDemoEntries.self, from: backup)
      check(decodedBackup.foods.count == relaunch.entries.foods.count && decodedBackup.weights.count == relaunch.entries.weights.count && decodedBackup.activities.count == relaunch.entries.activities.count, "Backup must preserve all local record types")
      check(decodedBackup.energyGoal == relaunch.energyGoal && decodedBackup.version == 3, "Backup must preserve goal and format version")
      let backupKeys = Set((try JSONSerialization.jsonObject(with: backup) as! [String: Any]).keys)
      check(backupKeys.isSubset(of: ["version", "foods", "activities", "weights", "energyGoal", "trash", "foodLibrary", "exerciseLibrary", "importNotes", "sourceArchive"]), "Backup must not contain API or generated example fields")
      let legacyURL = directory.appendingPathComponent("legacy.json")
      var legacy = HomeDemoEntries(); legacy.version = 1; legacy.foods = [input]
      let bytes = try JSONEncoder().encode(legacy); try bytes.write(to: legacyURL)
      let migrationStore = HomeDemoEntryStore(url: legacyURL)
      let migrated = HomeState(anchor: anchor, preload: true, entryStore: migrationStore, usesExamples: true)
      check(try Data(contentsOf: legacyURL) == bytes, "Reading an old file must not rewrite it")
      try migrated.setEnergyGoal(2200)
      check(try migrationStore.read().version == 3 && Data(contentsOf: directory.appendingPathComponent("entries-v1.backup.json")) == bytes, "First updated save must preserve the old file backup")
      try Data("bad".utf8).write(to: editsURL)
      relaunch.entry = nil; relaunch.refreshLocalEntries()
      check(relaunch.entryStorageError != nil, "Unreadable local file should be reported")
      try JSONEncoder().encode(HomeDemoEntries()).write(to: editsURL)
      relaunch.refreshLocalEntries(); try relaunch.setEnergyGoal(2000)
      check(relaunch.entryStorageError == nil && relaunch.energyGoal == 2000, "A repaired file should be readable without restarting")
    } catch { check(false, "Local record lifecycle failed: " + error.localizedDescription) }
    let finiteGoal = HomeEntryDraft(kind: .energy, date: anchor, goal: 1800.5)
    check(finiteGoal.goal == "1800.5", "Opening a fractional goal must not round it away")
    finiteGoal.adjustGoal(by: 50)
    check(finiteGoal.goal == "1850.5", "Goal stepper must preserve fractional input")
    finiteGoal.goal = "nan"; finiteGoal.adjustGoal(by: 50)
    check(finiteGoal.goal == "2050", "Nonfinite numeric text must not crash the stepper")
    let report: [String: Any] = ["ok": failures.isEmpty, "assertions": assertions, "failures": failures, "realDatabaseRead": false, "externalRequests": 0]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    if CommandLine.arguments.count > 1 { try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
    print(String(data: data, encoding: .utf8)!)
    exit(failures.isEmpty ? 0 : 1)
  }
}
