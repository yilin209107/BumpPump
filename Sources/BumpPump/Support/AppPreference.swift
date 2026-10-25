import SwiftUI
import Combine

/// Observe only the requested preference, after the current AppKit layout pass.
/// Window frame persistence also posts defaults notifications; refreshing a SwiftUI
/// graph synchronously from that notification can re-enter NSWindow constraints.
protocol AppPreferenceValue: Equatable {
  static func read(from defaults: UserDefaults, key: String) -> Self?
}
extension String: AppPreferenceValue {
  static func read(from defaults: UserDefaults, key: String) -> String? { defaults.string(forKey: key) }
}
extension Bool: AppPreferenceValue {
  static func read(from defaults: UserDefaults, key: String) -> Bool? {
    defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
  }
}
final class AppPreferenceObserver<Value: AppPreferenceValue>: ObservableObject {
  @Published private(set) var value: Value
  private let defaults: UserDefaults
  private let key: String
  private let fallback: Value
  private var notification: NSObjectProtocol?
  private var refreshPending = false
  init(defaultValue: Value, key: String, defaults: UserDefaults) {
    self.defaults = defaults; self.key = key; fallback = defaultValue
    value = Value.read(from: defaults, key: key) ?? defaultValue
    notification = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
      // Notifications can arrive on any thread, including in windowDidLayout.
      DispatchQueue.main.async { [weak self] in self?.scheduleRefresh() }
    }
  }
  deinit { if let notification { NotificationCenter.default.removeObserver(notification) } }
  func set(_ newValue: Value) {
    defaults.set(newValue, forKey: key)
    scheduleRefresh()
  }
  private func scheduleRefresh() {
    guard !refreshPending else { return }
    refreshPending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.refreshPending = false
      let next = Value.read(from: self.defaults, key: self.key) ?? self.fallback
      if next != self.value { self.value = next }
    }
  }
}
@propertyWrapper struct AppPreference<Value: AppPreferenceValue>: DynamicProperty {
  @StateObject private var observer: AppPreferenceObserver<Value>
  init(wrappedValue: Value, _ key: String, store: UserDefaults = .standard) {
    _observer = StateObject(wrappedValue: AppPreferenceObserver(defaultValue: wrappedValue, key: key, defaults: store))
  }
  var wrappedValue: Value {
    get { observer.value }
    nonmutating set { observer.set(newValue) }
  }
  var projectedValue: Binding<Value> { Binding(get: { observer.value }, set: { observer.set($0) }) }
}
