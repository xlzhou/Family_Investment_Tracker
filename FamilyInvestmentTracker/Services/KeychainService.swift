import Foundation
import Security
import CryptoKit

class KeychainService {
    static let shared = KeychainService()

    private let service = "com.familyinvestmenttracker.keychain"
    private let passcodeKey = "app_passcode"
    private let saltKey = "passcode_salt"
    private let failedAttemptsKey = "failed_attempts"
    private let lastFailedAttemptKey = "last_failed_attempt"

    private init() {}

    // MARK: - Password Management

    func setPasscode(_ passcode: String) -> Bool {
        // Generate a random salt for this passcode
        let salt = generateSalt()

        // Hash the passcode with salt using SHA256
        let hashedPasscode = hashPasscode(passcode, salt: salt)

        // Store both hashed passcode and salt in keychain
        let passcodeStored = storeInKeychain(key: passcodeKey, data: hashedPasscode)
        let saltStored = storeInKeychain(key: saltKey, data: salt)

        if passcodeStored && saltStored {
            // Reset failed attempts when new passcode is set
            resetFailedAttempts()
            return true
        }

        return false
    }

    func verifyPasscode(_ passcode: String) -> Bool {
        guard let storedSalt = retrieveFromKeychain(key: saltKey),
              let storedHashedPasscode = retrieveFromKeychain(key: passcodeKey) else {
            return false
        }

        // Hash the provided passcode with stored salt
        let hashedInput = hashPasscode(passcode, salt: storedSalt)

        // Compare with stored hash
        let isValid = hashedInput == storedHashedPasscode

        if isValid {
            resetFailedAttempts()
        } else {
            incrementFailedAttempts()
        }

        return isValid
    }

    func hasPasscodeSet() -> Bool {
        return retrieveFromKeychain(key: passcodeKey) != nil
    }

    func removePasscode() -> Bool {
        let passcodeRemoved = deleteFromKeychain(key: passcodeKey)
        let saltRemoved = deleteFromKeychain(key: saltKey)
        resetFailedAttempts()
        return passcodeRemoved && saltRemoved
    }

    // MARK: - Security Features

    func getFailedAttempts() -> Int {
        guard let data = retrieveFromKeychain(key: failedAttemptsKey),
              let attempts = String(data: data, encoding: .utf8),
              let count = Int(attempts) else {
            return 0
        }
        return count
    }

    func incrementFailedAttempts() {
        let currentAttempts = getFailedAttempts()
        let newAttempts = currentAttempts + 1

        let attemptsData = String(newAttempts).data(using: .utf8)!
        let timestampData = String(Date().timeIntervalSince1970).data(using: .utf8)!

        _ = storeInKeychain(key: failedAttemptsKey, data: attemptsData)
        _ = storeInKeychain(key: lastFailedAttemptKey, data: timestampData)
    }

    func resetFailedAttempts() {
        _ = deleteFromKeychain(key: failedAttemptsKey)
        _ = deleteFromKeychain(key: lastFailedAttemptKey)
    }

    func getTimeSinceLastFailedAttempt() -> TimeInterval {
        guard let data = retrieveFromKeychain(key: lastFailedAttemptKey),
              let timestampString = String(data: data, encoding: .utf8),
              let timestamp = Double(timestampString) else {
            return 0
        }

        return Date().timeIntervalSince1970 - timestamp
    }

    func isTemporarilyLocked() -> Bool {
        let failedAttempts = getFailedAttempts()
        let timeSinceLastAttempt = getTimeSinceLastFailedAttempt()

        // Progressive lockout: 1 min after 3 attempts, 5 min after 5 attempts, 15 min after 7+ attempts
        switch failedAttempts {
        case 3..<5:
            return timeSinceLastAttempt < 60 // 1 minute
        case 5..<7:
            return timeSinceLastAttempt < 300 // 5 minutes
        case 7...:
            return timeSinceLastAttempt < 900 // 15 minutes
        default:
            return false
        }
    }

    func getLockoutTimeRemaining() -> TimeInterval {
        guard isTemporarilyLocked() else { return 0 }

        let failedAttempts = getFailedAttempts()
        let timeSinceLastAttempt = getTimeSinceLastFailedAttempt()

        switch failedAttempts {
        case 3..<5:
            return 60 - timeSinceLastAttempt
        case 5..<7:
            return 300 - timeSinceLastAttempt
        case 7...:
            return 900 - timeSinceLastAttempt
        default:
            return 0
        }
    }

    // MARK: - Private Crypto Functions

    private func generateSalt() -> Data {
        var salt = Data(count: 32) // 256-bit salt
        let result = salt.withUnsafeMutableBytes { mutableBytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, mutableBytes.bindMemory(to: UInt8.self).baseAddress!)
        }

        guard result == errSecSuccess else {
            // Fallback to UUID-based salt if SecRandomCopyBytes fails
            return UUID().uuidString.data(using: .utf8)!
        }

        return salt
    }

    private func hashPasscode(_ passcode: String, salt: Data) -> Data {
        let passcodeData = passcode.data(using: .utf8)!
        let combined = passcodeData + salt

        // Use SHA256 for hashing
        let digest = SHA256.hash(data: combined)
        return Data(digest)
    }

    // MARK: - Keychain Operations

    private func storeInKeychain(key: String, data: Data) -> Bool {
        // First, delete any existing item
        _ = deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func retrieveFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return data
    }

    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}