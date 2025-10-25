import Foundation
import LocalAuthentication
import SwiftUI
import Security
import CryptoKit

enum AuthenticationState {
    case authenticated
    case needsPasscodeSetup
    case needsAuthentication
    case temporarilyLocked
    case passwordRecovery
}

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authenticationError: String?
    @Published var authenticationState: AuthenticationState = .needsAuthentication
    @Published var lockoutTimeRemaining: TimeInterval = 0

    private var lockoutTimer: Timer?
    private var logoutTimer: Timer?
    private var lastBackgroundTime: Date?
    private var statusRetryWorkItem: DispatchWorkItem?
    private var lastKnownPasswordPresence: PasswordPresence?

    // Security Questions Manager
    let securityQuestionManager = SecurityQuestionManager()

    private enum PasswordPresence {
        case present
        case absent
    }

    // Logout configuration
    private let logoutDelaySeconds: TimeInterval = 15 // 15 seconds delay before auto-logout
    private let maxBackgroundTimeMinutes: TimeInterval = 5 // 5 minutes max background time

    // Keychain keys
    private let service = "com.familyinvestmenttracker.keychain"
    private let passwordKey = "app_password"
    private let saltKey = "password_salt"
    private let failedAttemptsKey = "failed_attempts"
    private let lastFailedAttemptKey = "last_failed_attempt"
    
    private func makeContext() -> LAContext {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = localized("auth.biometric.fallback")
        return ctx
    }

    init() {
        checkAuthenticationStatus()
    }

    private func localized(_ key: String) -> String {
        LocalizationManager.shared.localizedString(for: key)
    }

    func checkAuthenticationStatus() {
        switch determinePasswordPresence() {
        case .present:
            cancelPendingStatusRetry()
            lastKnownPasswordPresence = .present

            if isTemporarilyLocked() {
                authenticationState = .temporarilyLocked
                isAuthenticated = false
                startLockoutTimer()
            } else {
                authenticationState = .needsAuthentication
                isAuthenticated = false
            }

        case .absent:
            cancelPendingStatusRetry()
            lastKnownPasswordPresence = .absent
            authenticationState = .needsPasscodeSetup
            isAuthenticated = false

        case .unknown:
            // Preserve the most recent valid state to avoid flashing the setup UI
            if lastKnownPasswordPresence == .present && authenticationState == .needsPasscodeSetup {
                authenticationState = .needsAuthentication
            }
            isAuthenticated = false
            scheduleStatusRetry()
        }
    }
    
    func authenticateWithBiometrics() {
        let context = makeContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            authenticationError = localized("auth.error.biometricUnavailable")
            return
        }
        
        let reason = localized("auth.biometric.reason")
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                    self?.authenticationError = nil
                } else {
                    self?.authenticationError = error?.localizedDescription ?? self?.localized("auth.error.generic")
                }
            }
        }
    }
    
    // MARK: - App Passcode Authentication

    func authenticateWithAppPassword(_ password: String) {
        guard !isTemporarilyLocked() else {
            authenticationError = localized("auth.error.tooManyAttemptsWait")
            return
        }

        if verifyPassword(password) {
            isAuthenticated = true
            authenticationState = .authenticated
            authenticationError = nil
            stopLockoutTimer()
        } else {
            authenticationError = localized("auth.error.incorrectPasscode")

            // Check if now temporarily locked
            if isTemporarilyLocked() {
                authenticationState = .temporarilyLocked
                startLockoutTimer()
                let timeRemaining = getLockoutTimeRemaining()
                authenticationError = String(format: localized("auth.error.lockedMinutes"),
                                             Int(timeRemaining / 60))
            }
        }
    }

    func setAppPassword(_ password: String) -> Bool {
        if setPassword(password) {
            authenticationState = .needsAuthentication
            authenticationError = nil
            lastKnownPasswordPresence = .present
            return true
        } else {
            authenticationError = localized("auth.error.setPasscodeFailed")
            return false
        }
    }

    func changeAppPassword(currentPassword: String, newPassword: String) -> Bool {
        guard verifyPassword(currentPassword) else {
            authenticationError = localized("auth.error.currentPasscodeIncorrect")
            return false
        }

        return setAppPassword(newPassword)
    }

    func removeAppPassword(currentPassword: String) -> Bool {
        guard verifyPassword(currentPassword) else {
            authenticationError = localized("auth.error.currentPasscodeIncorrect")
            return false
        }

        if removePassword() {
            authenticationState = .needsPasscodeSetup
            authenticationError = nil
            lastKnownPasswordPresence = .absent
            return true
        } else {
            authenticationError = localized("auth.error.removePasscodeFailed")
            return false
        }
    }

    // MARK: - Password Recovery

    func startPasswordRecovery() {
        authenticationState = .passwordRecovery
        authenticationError = nil
    }

    func cancelPasswordRecovery() {
        authenticationState = .needsAuthentication
        authenticationError = nil
    }

    func recoverPasswordWithBiometrics(completion: @escaping (Bool) -> Void) {
        let context = makeContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            authenticationError = localized("auth.error.biometricUnavailable")
            completion(false)
            return
        }

        let reason = String(format: localized("auth.biometric.reason.reset"),
                            getBiometricType())

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.authenticationError = nil
                    completion(true)
                } else {
                    self?.authenticationError = error?.localizedDescription ?? self?.localized("auth.error.biometricFailed")
                    completion(false)
                }
            }
        }
    }

    func recoverPasswordWithSecurityQuestions(_ answers: [(questionId: String, answer: String)]) -> Bool {
        if securityQuestionManager.verifySecurityQuestions(answers) {
            authenticationError = nil
            return true
        } else {
            authenticationError = localized("auth.error.securityQuestionsIncorrect")
            return false
        }
    }

    func resetPasswordAfterRecovery(_ newPassword: String) -> Bool {
        // Reset password without requiring current password
        if setPasswordDirectly(newPassword) {
            authenticationState = .needsAuthentication
            authenticationError = nil
            lastKnownPasswordPresence = .present
            return true
        } else {
            authenticationError = localized("auth.error.resetPasscodeFailed")
            return false
        }
    }

    func hasSecurityQuestionsSetup() -> Bool {
        return securityQuestionManager.hasSecurityQuestionsSetup()
    }

    func getSecurityQuestionsForRecovery() -> [SecurityQuestion]? {
        return securityQuestionManager.getSecurityQuestions()
    }
    
    func logout() {
        isAuthenticated = false
        authenticationState = .needsAuthentication
        authenticationError = nil
        stopLockoutTimer()
        stopLogoutTimer()
        cancelPendingStatusRetry()
    }

    // MARK: - Background/Foreground Management

    func handleAppDidEnterBackground() {
        lastBackgroundTime = Date()

        // Don't start logout timer during password setup to allow AutoFill
        guard authenticationState != .needsPasscodeSetup else {
            print("🔒 Skipping logout timer during password setup")
            return
        }

        // Start delayed logout timer
        startLogoutTimer()
    }

    func handleAppWillEnterForeground() {
        // Always stop logout timer when app becomes active
        stopLogoutTimer()

        // Check if we've been in background too long (only if we have a background time)
        if let backgroundTime = lastBackgroundTime {
            let backgroundDuration = Date().timeIntervalSince(backgroundTime)
            let maxDuration = maxBackgroundTimeMinutes * 60

            if backgroundDuration > maxDuration {
                print("🔒 App was in background for \(backgroundDuration)s, logging out")
                logout()
            } else {
                print("🔒 App returned within \(backgroundDuration)s, staying logged in")
            }

            // Only clear background time - don't restart any timers
            lastBackgroundTime = nil
        } else {
            print("🔒 App became active, logout timer stopped")
        }
    }

    private func startLogoutTimer() {
        stopLogoutTimer()

        print("🔒 Starting logout timer for \(logoutDelaySeconds)s")
        logoutTimer = Timer.scheduledTimer(withTimeInterval: logoutDelaySeconds, repeats: false) { [weak self] _ in
            print("🔒 Logout timer expired, logging out")
            self?.logout()
        }
    }

    private func stopLogoutTimer() {
        logoutTimer?.invalidate()
        logoutTimer = nil
    }

    func extendSession() {
        // Reset logout timer when user is actively using the app
        if logoutTimer != nil {
            startLogoutTimer()
        }
    }
    
    func getBiometricType() -> String {
        let context = makeContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return localized("auth.biometric.faceID")
        case .touchID:
            return localized("auth.biometric.touchID")
        case .opticID:
            return localized("auth.biometric.opticID")
        case .none:
            return localized("auth.biometric.generic")
        @unknown default:
            return localized("auth.biometric.generic")
        }
    }

    func isBiometricAvailable() -> Bool {
        let context = makeContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    // MARK: - Security Features

    private func startLockoutTimer() {
        stopLockoutTimer()

        lockoutTimeRemaining = getLockoutTimeRemaining()

        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.lockoutTimeRemaining = self.getLockoutTimeRemaining()

            if self.lockoutTimeRemaining <= 0 {
                self.stopLockoutTimer()
                self.checkAuthenticationStatus()
            }
        }
    }

    private func stopLockoutTimer() {
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        lockoutTimeRemaining = 0
    }

    func getLockoutTimeRemainingString() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = lockoutTimeRemaining >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: lockoutTimeRemaining) ?? String(format: "%.0f", lockoutTimeRemaining)
    }

    // MARK: - Private Keychain Methods

    private func setPassword(_ password: String) -> Bool {
        let salt = generateSalt()
        let hashedPassword = hashPassword(password, salt: salt)

        let passwordStored = storeInKeychain(key: passwordKey, data: hashedPassword)
        let saltStored = storeInKeychain(key: saltKey, data: salt)

        if passwordStored && saltStored {
            resetFailedAttempts()
            return true
        }
        return false
    }

    // Set password directly without verification (for recovery)
    private func setPasswordDirectly(_ password: String) -> Bool {
        let salt = generateSalt()
        let hashedPassword = hashPassword(password, salt: salt)

        let passwordStored = storeInKeychain(key: passwordKey, data: hashedPassword)
        let saltStored = storeInKeychain(key: saltKey, data: salt)

        if passwordStored && saltStored {
            resetFailedAttempts()
            return true
        }
        return false
    }

    private func verifyPassword(_ password: String) -> Bool {
        guard let storedSalt = retrieveFromKeychain(key: saltKey),
              let storedHashedPassword = retrieveFromKeychain(key: passwordKey) else {
            return false
        }

        let hashedInput = hashPassword(password, salt: storedSalt)
        let isValid = hashedInput == storedHashedPassword

        if isValid {
            resetFailedAttempts()
        } else {
            incrementFailedAttempts()
        }

        return isValid
    }

    private func removePassword() -> Bool {
        let passwordRemoved = deleteFromKeychain(key: passwordKey)
        let saltRemoved = deleteFromKeychain(key: saltKey)
        resetFailedAttempts()
        return passwordRemoved && saltRemoved
    }

    private func getFailedAttempts() -> Int {
        guard let data = retrieveFromKeychain(key: failedAttemptsKey),
              let attempts = String(data: data, encoding: .utf8),
              let count = Int(attempts) else {
            return 0
        }
        return count
    }

    private func incrementFailedAttempts() {
        let currentAttempts = getFailedAttempts()
        let newAttempts = currentAttempts + 1

        let attemptsData = String(newAttempts).data(using: .utf8)!
        let timestampData = String(Date().timeIntervalSince1970).data(using: .utf8)!

        _ = storeInKeychain(key: failedAttemptsKey, data: attemptsData)
        _ = storeInKeychain(key: lastFailedAttemptKey, data: timestampData)
    }

    private func resetFailedAttempts() {
        _ = deleteFromKeychain(key: failedAttemptsKey)
        _ = deleteFromKeychain(key: lastFailedAttemptKey)
    }

    private func getTimeSinceLastFailedAttempt() -> TimeInterval {
        guard let data = retrieveFromKeychain(key: lastFailedAttemptKey),
              let timestampString = String(data: data, encoding: .utf8),
              let timestamp = Double(timestampString) else {
            return 0
        }
        return Date().timeIntervalSince1970 - timestamp
    }

    private func isTemporarilyLocked() -> Bool {
        let failedAttempts = getFailedAttempts()
        let timeSinceLastAttempt = getTimeSinceLastFailedAttempt()

        switch failedAttempts {
        case 3..<5:
            return timeSinceLastAttempt < 60
        case 5..<7:
            return timeSinceLastAttempt < 300
        case 7...:
            return timeSinceLastAttempt < 900
        default:
            return false
        }
    }

    private func getLockoutTimeRemaining() -> TimeInterval {
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

    private func generateSalt() -> Data {
        var salt = Data(count: 32)
        let result = salt.withUnsafeMutableBytes { mutableBytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, mutableBytes.bindMemory(to: UInt8.self).baseAddress!)
        }

        guard result == errSecSuccess else {
            return UUID().uuidString.data(using: .utf8)!
        }
        return salt
    }

    private func hashPassword(_ password: String, salt: Data) -> Data {
        let passwordData = password.data(using: .utf8)!
        let combined = passwordData + salt
        let digest = SHA256.hash(data: combined)
        return Data(digest)
    }

    private func storeInKeychain(key: String, data: Data) -> Bool {
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

    private func retrieveFromKeychain(key: String, retryCount: Int = 0) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            return data
        }

        if status == errSecItemNotFound {
            return nil
        }

        if shouldRetryKeychain(status: status, currentRetryCount: retryCount) {
            let delay = useconds_t((retryCount + 1) * 150_000)
            usleep(delay)
            return retrieveFromKeychain(key: key, retryCount: retryCount + 1)
        }

        logKeychainFailure(status: status, for: key)
        return nil
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

    private enum PasswordPresenceResult {
        case present
        case absent
        case unknown
    }

    private func determinePasswordPresence() -> PasswordPresenceResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordKey,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return .present
        case errSecItemNotFound:
            return .absent
        case errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed:
            return .unknown
        default:
            if status != errSecItemNotFound && status != errSecSuccess {
                logKeychainFailure(status: status, for: passwordKey)
            }
            return .unknown
        }
    }

    private func scheduleStatusRetry(after delay: TimeInterval = 0.3) {
        guard statusRetryWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.statusRetryWorkItem = nil
            self?.checkAuthenticationStatus()
        }
        statusRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingStatusRetry() {
        statusRetryWorkItem?.cancel()
        statusRetryWorkItem = nil
    }

    private func shouldRetryKeychain(status: OSStatus, currentRetryCount: Int) -> Bool {
        guard currentRetryCount < 3 else { return false }

        switch status {
        case errSecInteractionNotAllowed, errSecNotAvailable, errSecAuthFailed:
            return true
        default:
            return false
        }
    }

    private func logKeychainFailure(status: OSStatus, for key: String) {
        guard status != errSecItemNotFound else { return }

        if let message = SecCopyErrorMessageString(status, nil) {
            print("🔒 Keychain error for \(key): \(message as String)")
        } else {
            print("🔒 Keychain error for \(key): status \(status)")
        }
    }
}
