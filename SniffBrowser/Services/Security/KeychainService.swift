import Foundation
import Security

enum KeychainServiceError: Error {
  case unexpectedStatus(OSStatus)
  case invalidData
}

struct KeychainService {
  private let service: String

  init(service: String = Bundle.main.bundleIdentifier ?? "com.example.SniffBrowser") {
    self.service = service
  }

  func save(_ data: Data, for account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] =
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainServiceError.unexpectedStatus(status)
    }
  }

  func read(for account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw KeychainServiceError.unexpectedStatus(status)
    }
    guard let data = result as? Data else {
      throw KeychainServiceError.invalidData
    }
    return data
  }

  func delete(for account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainServiceError.unexpectedStatus(status)
    }
  }
}
