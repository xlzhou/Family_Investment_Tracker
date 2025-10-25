import SwiftUI
import Foundation

struct NewPasswordSetupView: View {
    @ObservedObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
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

                    Text(localizationManager.localizedString(for: "newPasswordSetup.recoverySuccessful"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(recoveryMethodText)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    Text(localizationManager.localizedString(for: "newPasswordSetup.setNewPasscode"))
                        .font(.headline)
                        .fontWeight(.semibold)

                    // New Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizationManager.localizedString(for: "newPasswordSetup.newPasscode"))
                            .font(.body)
                            .fontWeight(.medium)

                        SecureField(localizationManager.localizedString(for: "newPasswordSetup.enterNewPasscode"), text: $newPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    // Confirm Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizationManager.localizedString(for: "newPasswordSetup.confirmPasscode"))
                            .font(.body)
                            .fontWeight(.medium)

                        SecureField(localizationManager.localizedString(for: "newPasswordSetup.confirmNewPasscode"), text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    // Password Requirements
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizationManager.localizedString(for: "newPasswordSetup.passcodeRequirements"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        RequirementText(
                            text: localizationManager.localizedString(for: "newPasswordSetup.requirement.length"),
                            isMet: newPassword.count >= 8
                        )

                        RequirementText(
                            text: localizationManager.localizedString(for: "newPasswordSetup.requirement.complexity"),
                            isMet: hasLettersAndNumbers(newPassword)
                        )

                        RequirementText(
                            text: localizationManager.localizedString(for: "newPasswordSetup.requirement.match"),
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
                        Text(isSettingPassword ? localizationManager.localizedString(for: "newPasswordSetup.settingPasscode") : localizationManager.localizedString(for: "newPasswordSetup.setNewPasscodeButton"))
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
            .navigationTitle(localizationManager.localizedString(for: "newPasswordSetup.navigationTitle"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "newPasswordSetup.cancel")) {
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
            return String(format: localizationManager.localizedString(for: "newPasswordSetup.biometricRecovery"), authManager.getBiometricType())
        case .securityQuestions:
            return localizationManager.localizedString(for: "newPasswordSetup.securityQuestionsRecovery")
        case .none:
            return localizationManager.localizedString(for: "newPasswordSetup.defaultMessage")
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
    .environmentObject(LocalizationManager.shared)
}