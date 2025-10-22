import SwiftUI
import Foundation

struct NewPasswordSetupView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isPresented: Bool
    let recoveryMethod: RecoveryMethod

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSettingPassword = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Success Header
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Recovery Successful!")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(recoveryMethodText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    Text("Set New Passcode")
                        .font(.headline)
                        .fontWeight(.semibold)

                    // New Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Passcode")
                            .font(.body)
                            .fontWeight(.medium)

                        SecureField("Enter new passcode", text: $newPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    // Confirm Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Passcode")
                            .font(.body)
                            .fontWeight(.medium)

                        SecureField("Confirm new passcode", text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    // Password Requirements
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passcode Requirements:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        RequirementText(
                            text: "At least 8 characters",
                            isMet: newPassword.count >= 8
                        )

                        RequirementText(
                            text: "Contains letters and numbers",
                            isMet: hasLettersAndNumbers(newPassword)
                        )

                        RequirementText(
                            text: "Passcodes match",
                            isMet: !newPassword.isEmpty && !confirmPassword.isEmpty && newPassword == confirmPassword
                        )
                    }
                    .padding(.top, 8)
                }

                // Error Message
                if let error = authManager.authenticationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Set Password Button
                Button(action: setNewPassword) {
                    HStack {
                        if isSettingPassword {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text(isSettingPassword ? "Setting Passcode..." : "Set New Passcode")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSetPassword ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canSetPassword || isSettingPassword)
            }
            .padding()
            .navigationTitle("New Passcode")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        authManager.cancelPasswordRecovery()
                        isPresented = false
                    }
                }
            }
        }
    }

    private var recoveryMethodText: String {
        switch recoveryMethod {
        case .biometric:
            return "Your identity was verified using \(authManager.getBiometricType()). Now set a new passcode to secure your app."
        case .securityQuestions:
            return "Your identity was verified using your security questions. Now set a new passcode to secure your app."
        case .none:
            return "Please set a new passcode to secure your app."
        }
    }

    private var canSetPassword: Bool {
        !isSettingPassword &&
        newPassword.count >= 8 &&
        hasLettersAndNumbers(newPassword) &&
        newPassword == confirmPassword &&
        !newPassword.isEmpty
    }

    private func hasLettersAndNumbers(_ password: String) -> Bool {
        let hasLetters = password.rangeOfCharacter(from: .letters) != nil
        let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
        return hasLetters && hasNumbers
    }

    private func setNewPassword() {
        isSettingPassword = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if authManager.resetPasswordAfterRecovery(newPassword) {
                isSettingPassword = false
                isPresented = false
            } else {
                isSettingPassword = false
            }
        }
    }
}

struct RequirementText: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? .green : .secondary)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

#Preview {
    NewPasswordSetupView(
        authManager: AuthenticationManager(),
        isPresented: Binding.constant(true),
        recoveryMethod: .biometric
    )
}