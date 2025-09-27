import SwiftUI

struct PasscodeSetupView: View {
    @EnvironmentObject var authManager: AuthenticationManager
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

                    Text("Set Up App Passcode")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Create a secure passcode to protect your investment data")
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
                            Text("Enter Passcode")
                                .font(.headline)
                                .foregroundColor(.primary)

                            SecureField("Passcode", text: $passcode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .onSubmit {
                                    if isValidPasscode(passcode) {
                                        showingConfirmation = true
                                    }
                                }

                            Text("Use 4-6 digits")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Confirmation entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Passcode")
                                .font(.headline)
                                .foregroundColor(.primary)

                            SecureField("Confirm Passcode", text: $confirmPasscode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                                .onSubmit {
                                    setupPasscode()
                                }

                            Text("Enter the same passcode again")
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
                                setupError = "Passcode must be 4-6 digits"
                            }
                        }) {
                            Text("Continue")
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
                            Text("Set Passcode")
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
                            Text("Back")
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
            .navigationTitle("Security Setup")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }

    private func isValidPasscode(_ passcode: String) -> Bool {
        return passcode.count >= 4 && passcode.count <= 6 && passcode.allSatisfy { $0.isNumber }
    }

    private func setupPasscode() {
        guard passcode == confirmPasscode else {
            setupError = "Passcodes don't match"
            return
        }

        guard isValidPasscode(passcode) else {
            setupError = "Invalid passcode format"
            return
        }

        if authManager.setAppPasscode(passcode) {
            // Success - the authentication manager will update its state
            setupError = nil
        } else {
            setupError = authManager.authenticationError ?? "Failed to set passcode"
        }
    }
}

#Preview {
    PasscodeSetupView()
        .environmentObject(AuthenticationManager())
}