import CryptoKit
import Foundation
import Darwin

/// App-managed, local-only storage without Keychain or password prompts.
/// The per-installation encryption key is protected by file permissions, not an OS vault.
final class LocalAPIKeyStore: @unchecked Sendable {
  static let shared = LocalAPIKeyStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("app.bumppump.mac/SecureStore", isDirectory: true))
  private let directory: URL
  private let lock = NSLock()
  private let context = Data("BumpPumpAPIKeys.v1".utf8)
  private var keyURL: URL { directory.appendingPathComponent("installation.key") }
  private var credentialsURL: URL { directory.appendingPathComponent("credentials.enc") }
  init(directory: URL) { self.directory = directory }

  func read(provider: String) throws -> String? {
    lock.lock(); defer { lock.unlock() }
    guard FileManager.default.fileExists(atPath: credentialsURL.path) else { return nil }
    return try credentials()[provider]
  }
  func save(_ value: String, provider: String) throws {
    lock.lock(); defer { lock.unlock() }
    try prepareDirectory()
    let existing = FileManager.default.fileExists(atPath: credentialsURL.path)
    var values = existing ? try credentials() : [:]
    values[provider] = value
    let key = try encryptionKey(create: !existing)
    let sealed = try AES.GCM.seal(JSONEncoder().encode(values), using: key, authenticating: context)
    guard let data = sealed.combined else { throw StoreError.invalidData }
    try data.write(to: credentialsURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path)
  }
  private func prepareDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }
  private func credentials() throws -> [String: String] {
    let box = try AES.GCM.SealedBox(combined: Data(contentsOf: credentialsURL))
    let data = try AES.GCM.open(box, using: encryptionKey(create: false), authenticating: context)
    return try JSONDecoder().decode([String: String].self, from: data)
  }
  private func encryptionKey(create: Bool) throws -> SymmetricKey {
    if !FileManager.default.fileExists(atPath: keyURL.path) {
      guard create else { throw StoreError.missingKey }
      let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
      // Exclusive creation prevents replacing another app instance's installation key.
      let descriptor = open(keyURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
      if descriptor >= 0 {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do { try handle.write(contentsOf: key); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
      } else if errno != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    let key = try Data(contentsOf: keyURL)
    guard key.count == 32 else { throw StoreError.invalidData }
    return SymmetricKey(data: key)
  }
  private enum StoreError: Error { case missingKey, invalidData }
}
