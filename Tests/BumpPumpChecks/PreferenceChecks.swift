import Foundation
import Combine

@main enum PreferenceChecks {
  static func main() {
    let suite = "app.bumppump.preference-check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var checks = 0
    func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    let tab = AppPreferenceObserver(defaultValue: "ai", key: "BumpPump.settingsTab", defaults: defaults)
    var changes = 0
    let subscription = tab.objectWillChange.sink { changes += 1 }
    check(tab.value == "ai", "Missing keys use the existing default")
    for index in 0..<200 {
      defaults.set("frame \(index)", forKey: "NSWindow Frame Test")
      NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
    check(changes == 0, "Frame persistence cannot invalidate SwiftUI during window layout")
    settle()
    check(changes == 0, "Unrelated defaults must not invalidate the view at all")
    defaults.set("about", forKey: "BumpPump.settingsTab")
    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    check(changes == 0, "External changes are deferred until after layout")
    settle()
    check(tab.value == "about" && changes == 1, "Actual key changes publish once")
    tab.set("data"); tab.set("ai")
    check(tab.value == "about" && changes == 1, "Writes cannot synchronously re-enter layout")
    settle()
    check(tab.value == "ai" && changes == 2, "Rapid writes coalesce to their latest value")
    tab.set("ai"); settle()
    check(changes == 2, "Writing the same value does not invalidate the graph")
    defaults.removeObject(forKey: "BumpPump.settingsTab")
    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    settle()
    check(tab.value == "ai" && changes == 2, "Removing a default with the same effective value is stable")
    defaults.set(true, forKey: "assistant.shortcutsHintShown")
    let hint = AppPreferenceObserver(defaultValue: false, key: "assistant.shortcutsHintShown", defaults: defaults)
    check(hint.value, "Existing first-use preferences remain intact")
    defaults.set("yilin209107/BumpPump", forKey: "BumpPump.updateRepository")
    let repository = AppPreferenceObserver(defaultValue: "", key: "BumpPump.updateRepository", defaults: defaults)
    check(repository.value == "yilin209107/BumpPump", "Existing repository preferences remain intact")
    defaults.set("data", forKey: "BumpPump.settingsTab")
    let backgroundPost = DispatchGroup()
    backgroundPost.enter()
    DispatchQueue.global().async {
      NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
      backgroundPost.leave()
    }
    backgroundPost.wait(); settle()
    check(tab.value == "data" && changes == 3, "Background notifications are delivered on the main run loop")
    withExtendedLifetime(subscription) {}
    print("Preference checks: \(checks) assertions passed")
  }
}
