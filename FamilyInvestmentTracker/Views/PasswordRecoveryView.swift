import SwiftUI
import LocalAuthentication

enum RecoveryMethod {
    case none
    case biometric
    case securityQuestions
}

struct PasswordRecoveryView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var showingSecurityQuestions = false
    @State private var showingNewPasswordSetup = false
    @State private var recoveryMethod: RecoveryMethod = .none

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Forgot Your Passcode?")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose a recovery method to reset your passcode")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                // Biometric Recovery Option
                if authManager.isBiometricAvailable() {
                    RecoveryOptionButton(
                        icon: getBiometricIcon(),
                        title: "Use \(authManager.getBiometricType())",
                        subtitle: "Authenticate with \(authManager.getBiometricType()) to reset your passcode",
                        action: {
                            attemptBiometricRecovery()
                        }
                    )
                }

                // Security Questions Recovery Option
                if authManager.hasSecurityQuestionsSetup() {
                    RecoveryOptionButton(
                        icon: "questionmark.circle.fill",
                        title: "Answer Security Questions",
                        subtitle: "Answer your security questions to reset your passcode",
                        action: {
                            showingSecurityQuestions = true
                        }
                    )
                }

                // No recovery options available
                if !authManager.isBiometricAvailable() && !authManager.hasSecurityQuestionsSetup() {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text("No Recovery Options Available")
                            .font(.headline)
                            .fontWeight(.bold)

                        Text("You haven't set up any recovery methods. Unfortunately, there's no way to recover your passcode without losing your data.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Text("You'll need to delete and reinstall the app to start fresh.")
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }

            Spacer()

            // Cancel Button
            Button("Cancel") {
                authManager.cancelPasswordRecovery()
            }
            .font(.body)
            .foregroundColor(.blue)

            // Error Message
            if let error = authManager.authenticationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .sheet(isPresented: $showingSecurityQuestions) {
            SecurityQuestionsRecoveryView(authManager: authManager, isPresented: $showingSecurityQuestions, onSuccess: {
                recoveryMethod = .securityQuestions
                showingNewPasswordSetup = true
            })
        }
        .sheet(isPresented: $showingNewPasswordSetup) {
            NewPasswordSetupView(authManager: authManager, isPresented: $showingNewPasswordSetup, recoveryMethod: recoveryMethod)
        }
    }

    private func getBiometricIcon() -> String {
        switch authManager.getBiometricType() {
        case "Face ID":
            return "faceid"
        case "Touch ID":
            return "touchid"
        case "Optic ID":
            return "opticid"
        default:
            return "person.fill.checkmark"
        }
    }

    private func attemptBiometricRecovery() {
        authManager.recoverPasswordWithBiometrics { success in
            if success {
                recoveryMethod = .biometric
                showingNewPasswordSetup = true
            }
        }
    }
}

struct RecoveryOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(.blue)
                    .frame(width: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    PasswordRecoveryView(authManager: AuthenticationManager())
}
