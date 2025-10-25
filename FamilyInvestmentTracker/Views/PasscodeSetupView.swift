import SwiftUI

struct PasscodeSetupView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var showingConfirmation = false
    @State private var setupError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                // Header
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text(localizationManager.localizedString(for: "passcodeSetup.title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(localizationManager.localizedString(for: "passcodeSetup.subtitle"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Passcode Input
                VStack(spacing: 20) {
                    if !showingConfirmation {
                        // Initial passcode entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizationManager.localizedString(for: "passcodeSetup.enterPasscode"))
                                .font(.headline)
                                .foregroundColor(.primary)

                            SecureField(localizationManager.localizedString(for: "passcodeSetup.passcodeInput"), text: $passcode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .onSubmit {
                                    if isValidPasscode(passcode) {
                                        showingConfirmation = true
                                    }
                                }

                            Text(localizationManager.localizedString(for: "passcodeSetup.passcodeHint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Confirmation entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizationManager.localizedString(for: "passcodeSetup.confirmPasscode"))
                                .font(.headline)
                                .foregroundColor(.primary)

                            SecureField(localizationManager.localizedString(for: "passcodeSetup.confirmPasscodeInput"), text: $confirmPasscode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .onSubmit {
                                    setupPasscode()
                                }

                            Text(localizationManager.localizedString(for: "passcodeSetup.confirmHint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 40)

                // Error Message
                if let error = setupError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Buttons
                VStack(spacing: 15) {
                    if !showingConfirmation {
                        Button(action: {
                            if isValidPasscode(passcode) {
                                showingConfirmation = true
                                setupError = nil
                            } else {
                                setupError = localizationManager.localizedString(for: "passcodeSetup.errorLength")
                            }
                        }) {
                            Text(localizationManager.localizedString(for: "passcodeSetup.continue"))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isValidPasscode(passcode) ? Color.blue : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(!isValidPasscode(passcode))
                    } else {
                        Button(action: setupPasscode) {
                            Text(localizationManager.localizedString(for: "passcodeSetup.setPasscode"))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(confirmPasscode == passcode && !confirmPasscode.isEmpty ? Color.blue : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(confirmPasscode != passcode || confirmPasscode.isEmpty)

                        Button(action: {
                            showingConfirmation = false
                            confirmPasscode = ""
                            setupError = nil
                        }) {
                            Text(localizationManager.localizedString(for: "passcodeSetup.back"))
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle(localizationManager.localizedString(for: "passcodeSetup.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }

    private func isValidPasscode(_ passcode: String) -> Bool {
        return passcode.count >= 4 && passcode.count <= 6 && passcode.allSatisfy { $0.isNumber }
    }

    private func setupPasscode() {
        guard passcode == confirmPasscode else {
            setupError = localizationManager.localizedString(for: "passcodeSetup.errorMismatch")
            return
        }

        guard isValidPasscode(passcode) else {
            setupError = localizationManager.localizedString(for: "passcodeSetup.errorInvalid")
            return
        }

        if authManager.setAppPasscode(passcode) {
            // Success - the authentication manager will update its state
            setupError = nil
        } else {
            setupError = authManager.authenticationError ?? localizationManager.localizedString(for: "passcodeSetup.errorFailed")
        }
    }
}

#Preview {
    PasscodeSetupView()
        .environmentObject(AuthenticationManager())
        .environmentObject(LocalizationManager.shared)
}