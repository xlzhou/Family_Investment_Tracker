import Foundation
import LocalAuthentication
import SwiftUI

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authenticationError: String?
    
    private let context = LAContext()
    
    init() {
        checkAuthenticationStatus()
    }
    
    func checkAuthenticationStatus() {
        // For development purposes, skip authentication
        // In production, this would check for valid session
        #if DEBUG
        isAuthenticated = false
        #else
        isAuthenticated = false
        #endif
    }
    
    func authenticateWithBiometrics() {
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            authenticationError = "Biometric authentication not available"
            return
        }
        
        let reason = "Authenticate to access your investment portfolio"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                    self?.authenticationError = nil
                } else {
                    self?.authenticationError = error?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }
    
    func authenticateWithPasscode() {
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            authenticationError = "Device authentication not available"
            return
        }
        
        let reason = "Authenticate to access your investment portfolio"
        
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                    self?.authenticationError = nil
                } else {
                    self?.authenticationError = error?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }
    
    func logout() {
        isAuthenticated = false
        authenticationError = nil
    }
    
    func getBiometricType() -> String {
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Passcode"
        @unknown default:
            return "Biometric"
        }
    }
}